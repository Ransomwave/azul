import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  buildRojoProject,
  findDefaultProjectFile,
  isGeneratedRojoProject,
  writeRojoProject,
} from "../rojoProject.js";
import type { SourcemapRoot } from "../pack.js";
import { RojoSnapshotBuilder } from "../snapshot/rojo/index.js";

function makeTempDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "azul-rojo-project-"));
}

function writeFile(dir: string, file: string, contents: string): void {
  fs.mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
  fs.writeFileSync(path.join(dir, file), contents, "utf8");
}

/**
 * ReplicatedStorage.Lib (a Folder) holding a module with a child module, a
 * Part, a Model pointing at the Part, and an ObjectValue pointing outside Lib.
 */
function packageSourcemap(): SourcemapRoot {
  return {
    name: "Game",
    className: "DataModel",
    children: [
      {
        name: "ReplicatedStorage",
        className: "ReplicatedStorage",
        guid: "rs",
        children: [
          {
            name: "Lib",
            className: "Folder",
            guid: "lib",
            children: [
              {
                name: "Util",
                className: "ModuleScript",
                guid: "util",
                filePaths: ["sync/ReplicatedStorage/Lib/Util.luau"],
                attributes: { Version: { String: "1.0.0" } },
                tags: ["Tagged"],
                children: [
                  {
                    name: "Inner",
                    className: "ModuleScript",
                    guid: "inner",
                    filePaths: ["sync/ReplicatedStorage/Lib/Util/Inner.luau"],
                  },
                ],
              },
              {
                name: "Part",
                className: "Part",
                guid: "part",
                properties: {
                  Size: { Vector3: [1, 2, 3] },
                  Anchored: { Bool: true },
                },
              },
              {
                name: "Model",
                className: "Model",
                guid: "model",
                properties: {
                  PrimaryPart: {
                    Ref: {
                      guid: "part",
                      path: ["ReplicatedStorage", "Lib", "Part"],
                    },
                  },
                },
              },
              {
                name: "Pointer",
                className: "ObjectValue",
                guid: "pointer",
                properties: {
                  Value: { Ref: { guid: "rs", path: ["ReplicatedStorage"] } },
                },
              },
            ],
          },
        ],
      },
    ],
  };
}

function writePackageScripts(tmp: string): void {
  writeFile(tmp, "sync/ReplicatedStorage/Lib/Util.luau", "return 'util'");
  writeFile(tmp, "sync/ReplicatedStorage/Lib/Util/Inner.luau", "return 1");
}

test("buildRojoProject describes a folder package root as an explicit Folder model", () => {
  const tmp = makeTempDir();
  try {
    const project = buildRojoProject(packageSourcemap(), {
      projectFile: path.join(tmp, "default.project.json"),
      baseDir: tmp,
      syncDir: path.join(tmp, "sync"),
      name: "MyPackage",
      packageRoot: path.join(tmp, "sync/ReplicatedStorage/Lib"),
    });

    assert.strictEqual(project.name, "MyPackage");
    assert.strictEqual(project.emitLegacyScripts, true);

    const tree = project.tree as Record<string, any>;
    assert.strictEqual(tree.$className, "Folder");
    assert.deepStrictEqual(tree.Util, {
      $path: "sync/ReplicatedStorage/Lib/Util.luau",
      $properties: { Tags: ["Tagged"] },
      $attributes: { Version: { String: "1.0.0" } },
      Inner: { $path: "sync/ReplicatedStorage/Lib/Util/Inner.luau" },
    });

    // Packed values are already in the explicit form Rojo reads.
    assert.deepStrictEqual(tree.Part, {
      $className: "Part",
      $id: "part",
      $properties: { Size: { Vector3: [1, 2, 3] }, Anchored: { Bool: true } },
    });

    assert.deepStrictEqual(tree.Model, {
      $className: "Model",
      $attributes: { Rojo_Target_PrimaryPart: "part" },
    });

    // A ref to something outside the package has nothing to point at.
    assert.deepStrictEqual(tree.Pointer, { $className: "ObjectValue" });
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("buildRojoProject roots a script pair package at the script, named after it", () => {
  const tmp = makeTempDir();
  try {
    const sourcemap: SourcemapRoot = {
      name: "Game",
      className: "DataModel",
      children: [
        {
          name: "ReplicatedStorage",
          className: "ReplicatedStorage",
          children: [
            {
              name: "Lib",
              className: "ModuleScript",
              guid: "lib",
              filePaths: ["sync/ReplicatedStorage/Lib.luau"],
              children: [
                {
                  name: "Child",
                  className: "ModuleScript",
                  filePaths: ["sync/ReplicatedStorage/Lib/Child.luau"],
                },
              ],
            },
          ],
        },
      ],
    };

    const expected = {
      $path: "sync/ReplicatedStorage/Lib.luau",
      Child: { $path: "sync/ReplicatedStorage/Lib/Child.luau" },
    };

    // Either half of the pair names the same root.
    for (const packageRoot of [
      "sync/ReplicatedStorage/Lib",
      "sync/ReplicatedStorage/Lib.luau",
    ]) {
      const project = buildRojoProject(sourcemap, {
        projectFile: path.join(tmp, "default.project.json"),
        baseDir: tmp,
        syncDir: path.join(tmp, "sync"),
        name: "MyPackage",
        packageRoot: path.join(tmp, packageRoot),
      });

      assert.strictEqual(project.name, "Lib");
      assert.deepStrictEqual(project.tree, expected);
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("buildRojoProject writes a place project when there's no package root", () => {
  const tmp = makeTempDir();
  try {
    const project = buildRojoProject(packageSourcemap(), {
      projectFile: path.join(tmp, "out", "game.project.json"),
      baseDir: tmp,
      syncDir: path.join(tmp, "sync"),
      name: "Game",
    });

    const tree = project.tree as Record<string, any>;
    assert.strictEqual(tree.$className, "DataModel");
    assert.strictEqual(tree.ReplicatedStorage.$className, "ReplicatedStorage");
    assert.strictEqual(tree.ReplicatedStorage.Lib.$className, "Folder");
    // Paths are relative to the project file's folder.
    assert.strictEqual(
      tree.ReplicatedStorage.Lib.Util.$path,
      "../sync/ReplicatedStorage/Lib/Util.luau",
    );
    // Inside a place, the ref target is part of the project.
    assert.deepStrictEqual(tree.ReplicatedStorage.$id, "rs");
    assert.deepStrictEqual(tree.ReplicatedStorage.Lib.Pointer.$attributes, {
      Rojo_Target_Value: "rs",
    });
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("buildRojoProject fails naming every instance a project can't key", () => {
  const tmp = makeTempDir();
  try {
    const sourcemap: SourcemapRoot = {
      name: "Game",
      className: "DataModel",
      children: [
        {
          name: "Workspace",
          className: "Workspace",
          children: [
            { name: "Door", className: "Model" },
            { name: "Door", className: "Model" },
            {
              name: "Folder",
              className: "Folder",
              children: [{ name: "$weird", className: "Part" }],
            },
          ],
        },
      ],
    };

    assert.throws(
      () =>
        buildRojoProject(sourcemap, {
          projectFile: path.join(tmp, "default.project.json"),
          baseDir: tmp,
          syncDir: path.join(tmp, "sync"),
          name: "Game",
        }),
      (error: Error) =>
        error.message.includes(
          'Workspace has more than one child named "Door"',
        ) && error.message.includes("Workspace.Folder.$weird"),
    );
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("buildRojoProject fails when the package root isn't in the sourcemap", () => {
  const tmp = makeTempDir();
  try {
    assert.throws(
      () =>
        buildRojoProject(packageSourcemap(), {
          projectFile: path.join(tmp, "default.project.json"),
          baseDir: tmp,
          syncDir: path.join(tmp, "sync"),
          name: "MyPackage",
          packageRoot: path.join(tmp, "sync/ServerStorage/Missing"),
        }),
      /isn't in the packed sourcemap/,
    );
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("A generated project reads back through Rojo compatibility mode", async () => {
  const tmp = makeTempDir();
  try {
    writePackageScripts(tmp);
    const projectFile = path.join(tmp, "default.project.json");

    const project = buildRojoProject(packageSourcemap(), {
      projectFile,
      baseDir: tmp,
      syncDir: path.join(tmp, "sync"),
      name: "MyPackage",
      packageRoot: path.join(tmp, "sync/ReplicatedStorage/Lib"),
    });
    writeRojoProject(
      project,
      projectFile,
      path.join(tmp, "pkg.sourcemap.json"),
    );

    assert.ok(isGeneratedRojoProject(projectFile));
    assert.match(
      fs.readFileSync(projectFile, "utf8"),
      /^\/\/ @generated by Azul from "pkg\.sourcemap\.json"/,
    );

    const instances = await new RojoSnapshotBuilder({
      cwd: tmp,
      projectFile,
      destPrefix: ["ReplicatedStorage", "MyPackage"],
    }).build();

    const byPath = (segments: string[]) => {
      const found = instances.find(
        (instance) => instance.path.join("/") === segments.join("/"),
      );
      assert.ok(found, `${segments.join("/")} was not emitted`);
      return found!;
    };

    const util = byPath(["ReplicatedStorage", "MyPackage", "Util"]);
    assert.strictEqual(util.className, "ModuleScript");
    assert.strictEqual(util.source, "return 'util'");
    assert.deepStrictEqual(util.attributes, { Version: { String: "1.0.0" } });

    const inner = byPath(["ReplicatedStorage", "MyPackage", "Util", "Inner"]);
    assert.strictEqual(inner.source, "return 1");

    const part = byPath(["ReplicatedStorage", "MyPackage", "Part"]);
    assert.deepStrictEqual(part.properties, {
      Size: { Vector3: [1, 2, 3] },
      Anchored: { Bool: true },
    });

    const model = byPath(["ReplicatedStorage", "MyPackage", "Model"]);
    assert.deepStrictEqual(model.properties?.PrimaryPart, {
      Ref: { guid: part.guid, path: part.path },
    });
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("isGeneratedRojoProject is false for a hand-written or missing project", () => {
  const tmp = makeTempDir();
  try {
    const projectFile = path.join(tmp, "default.project.json");
    assert.strictEqual(isGeneratedRojoProject(projectFile), false);

    writeFile(tmp, "default.project.json", '{ "name": "x", "tree": {} }');
    assert.strictEqual(isGeneratedRojoProject(projectFile), false);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("findDefaultProjectFile prefers default.project.json over .jsonc, as Rojo does", () => {
  const tmp = makeTempDir();
  try {
    assert.strictEqual(findDefaultProjectFile(tmp), null);

    writeFile(tmp, "default.project.jsonc", "{}");
    assert.strictEqual(
      findDefaultProjectFile(tmp),
      path.join(tmp, "default.project.jsonc"),
    );

    writeFile(tmp, "default.project.json", "{}");
    assert.strictEqual(
      findDefaultProjectFile(tmp),
      path.join(tmp, "default.project.json"),
    );
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

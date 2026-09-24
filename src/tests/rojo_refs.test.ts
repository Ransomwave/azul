import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { RojoSnapshotBuilder } from "../snapshot/rojo/index.js";
import type { InstanceData } from "../ipc/messages.js";

function makeTempDir(prefix = "azul-refs-") {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function write(dir: string, file: string, contents: unknown): void {
  fs.mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
  fs.writeFileSync(
    path.join(dir, file),
    typeof contents === "string" ? contents : JSON.stringify(contents, null, 2),
    "utf8",
  );
}

const byName = (instances: InstanceData[], name: string): InstanceData => {
  const found = instances.find((i) => i.name === name);
  assert.ok(found, `${name} was not emitted`);
  return found as InstanceData;
};

/** Mirrors Rojo's own ref_properties test project, covering all three id forms. */
test("RojoSnapshotBuilder links refs declared with $id, id and Rojo_Id", async () => {
  const tmp = makeTempDir();

  write(tmp, "ModelTarget.model.json", {
    id: "model target",
    className: "Folder",
    children: [
      {
        name: "ModelPointer",
        className: "Model",
        attributes: { Rojo_Target_PrimaryPart: "model target" },
      },
    ],
  });

  write(tmp, "default.project.json", {
    name: "refs",
    tree: {
      $className: "DataModel",
      Workspace: {
        ProjectTarget: {
          $className: "Folder",
          $id: "project target",
          ProjectPointer: {
            $className: "ObjectValue",
            // The fully qualified attribute form is accepted too.
            $attributes: { Rojo_Target_Value: { String: "project target" } },
          },
        },
        ModelTarget: { $path: "ModelTarget.model.json" },
        AttributeTarget: {
          $className: "Folder",
          $attributes: { Rojo_Id: "attribute target" },
        },
        CrossPointer: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: "attribute target" },
        },
      },
    },
  });

  const instances = await new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  }).build();

  const projectTarget = byName(instances, "ProjectTarget");
  const modelTarget = byName(instances, "ModelTarget");
  const attributeTarget = byName(instances, "AttributeTarget");

  // $id in a project file
  assert.deepStrictEqual(
    byName(instances, "ProjectPointer").properties?.Value,
    {
      Ref: { guid: projectTarget.guid, path: projectTarget.path },
    },
  );

  // id in a model file, pointed at from a child of that same model
  assert.deepStrictEqual(
    byName(instances, "ModelPointer").properties?.PrimaryPart,
    { Ref: { guid: modelTarget.guid, path: modelTarget.path } },
  );

  // Rojo_Id attribute, pointed at from a different subtree
  assert.deepStrictEqual(byName(instances, "CrossPointer").properties?.Value, {
    Ref: { guid: attributeTarget.guid, path: attributeTarget.path },
  });

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder honours both ids when a $path model root also declares one", async () => {
  const tmp = makeTempDir();

  // The project node and the model root it points at both name the same emitted
  // instance, so a pointer may use either id.
  write(tmp, "Target.model.json", { id: "model id", className: "Folder" });

  write(tmp, "default.project.json", {
    name: "refs",
    tree: {
      $className: "DataModel",
      Workspace: {
        Target: { $path: "Target.model.json", $id: "project id" },
        ByProjectId: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: "project id" },
        },
        ByModelId: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: "model id" },
        },
      },
    },
  });

  const instances = await new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  }).build();

  const target = byName(instances, "Target");
  const expected = { Ref: { guid: target.guid, path: target.path } };

  assert.deepStrictEqual(
    byName(instances, "ByProjectId").properties?.Value,
    expected,
  );
  assert.deepStrictEqual(
    byName(instances, "ByModelId").properties?.Value,
    expected,
  );

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder strips the ref attributes once they are linked", async () => {
  const tmp = makeTempDir();

  write(tmp, "default.project.json", {
    name: "refs",
    tree: {
      $className: "DataModel",
      Workspace: {
        Target: {
          $className: "Folder",
          $attributes: { Rojo_Id: "target", Keep: "me" },
        },
        Pointer: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: "target" },
        },
        Dangling: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: "nothing declares this" },
        },
      },
    },
  });

  const instances = await new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  }).build();

  // The link is carried by the property, so the directive attribute goes away.
  const pointer = byName(instances, "Pointer");
  assert.ok(pointer.properties?.Value, "the ref should still be linked");
  assert.strictEqual(pointer.attributes, undefined);

  // Unrelated attributes on a target survive; only Rojo_Id is taken off.
  assert.deepStrictEqual(byName(instances, "Target").attributes, {
    Keep: "me",
  });

  // An unresolved pointer is a directive too, so it is not left behind either.
  assert.strictEqual(byName(instances, "Dangling").attributes, undefined);

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder skips dangling and malformed refs without failing", async () => {
  const tmp = makeTempDir();

  write(tmp, "default.project.json", {
    name: "refs",
    tree: {
      $className: "DataModel",
      Workspace: {
        Dangling: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: "nothing declares this" },
        },
        Malformed: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: 42 },
        },
        // A bare prefix names no property, so there is nothing to set.
        BarePrefix: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_: "target" },
        },
      },
    },
  });

  const instances = await new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  }).build();

  assert.strictEqual(byName(instances, "Dangling").properties, undefined);
  assert.strictEqual(byName(instances, "Malformed").properties, undefined);
  assert.strictEqual(byName(instances, "BarePrefix").properties, undefined);

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder resolves a ref pointing forward to a later instance", async () => {
  const tmp = makeTempDir();

  write(tmp, "default.project.json", {
    name: "refs",
    tree: {
      $className: "DataModel",
      Workspace: {
        // Declared before its target exists, so linking has to be deferred.
        Pointer: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: "later" },
        },
        ZLater: { $className: "Folder", $id: "later" },
      },
    },
  });

  const instances = await new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  }).build();

  const target = byName(instances, "ZLater");
  assert.deepStrictEqual(byName(instances, "Pointer").properties?.Value, {
    Ref: { guid: target.guid, path: target.path },
  });

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder keeps the first of two identical ref ids", async () => {
  const tmp = makeTempDir();

  write(tmp, "default.project.json", {
    name: "refs",
    tree: {
      $className: "DataModel",
      Workspace: {
        AFirst: { $className: "Folder", $id: "shared" },
        BSecond: { $className: "Folder", $id: "shared" },
        Pointer: {
          $className: "ObjectValue",
          $attributes: { Rojo_Target_Value: "shared" },
        },
      },
    },
  });

  const instances = await new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  }).build();

  const first = byName(instances, "AFirst");
  assert.deepStrictEqual(byName(instances, "Pointer").properties?.Value, {
    Ref: { guid: first.guid, path: first.path },
  });

  fs.rmSync(tmp, { recursive: true, force: true });
});

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { RojoSnapshotBuilder } from "../snapshot/rojo/index.js";

function makeTempDir(prefix = "azul-test-") {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

test("RojoSnapshotBuilder builds instances from default.project.json and files", async () => {
  const tmp = makeTempDir();
  const modules = path.join(tmp, "Modules");
  fs.mkdirSync(modules, { recursive: true });
  const file = path.join(modules, "Foo.server.lua");
  fs.writeFileSync(file, "print('from rojo')", "utf8");

  const project = {
    name: "TestProj",
    tree: {
      $className: "DataModel",
      ReplicatedStorage: {
        Modules: {
          Foo: { $path: "Modules/Foo.server.lua" },
        },
      },
    },
  };

  fs.writeFileSync(
    path.join(tmp, "default.project.json"),
    JSON.stringify(project, null, 2),
    "utf8",
  );

  const builder = new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  });
  const instances = await builder.build();

  const script = instances.find(
    (i) => i.path.join("/") === "ReplicatedStorage/Modules/Foo",
  );
  assert.ok(script, "rojo script present");
  assert.strictEqual(script?.className, "Script");
  assert.strictEqual(script?.source?.includes("from rojo"), true);

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder handles init.luau in a folder as an init script", async () => {
  const tmp = makeTempDir();
  const dir = path.join(tmp, "modules", "MyModule");
  fs.mkdirSync(dir, { recursive: true });
  const initFile = path.join(dir, "init.luau");
  fs.writeFileSync(initFile, "print('init module')", "utf8");

  const project = {
    name: "InitProj",
    tree: {
      $className: "DataModel",
      ReplicatedStorage: {
        Modules: {
          MyModule: { $path: "modules/MyModule" },
        },
      },
    },
  };

  fs.writeFileSync(
    path.join(tmp, "default.project.json"),
    JSON.stringify(project, null, 2),
    "utf8",
  );

  const builder = new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  });
  const instances = await builder.build();

  const inst = instances.find(
    (i) => i.path.join("/") === "ReplicatedStorage/Modules/MyModule",
  );
  assert.ok(inst, "init-based instance emitted");
  assert.strictEqual(inst?.className, "ModuleScript");
  assert.strictEqual(typeof inst?.source, "string");
  assert.ok(inst?.source?.includes("init module"));

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder rewrites @self/ using the Azul instance name", async () => {
  const tmp = makeTempDir();
  const dir = path.join(tmp, "modules", "MyModule");
  fs.mkdirSync(dir, { recursive: true });

  // init.luau and Foo.server.lua both carry names that differ from the
  // instance they become, so the rewrite has to run post-conversion.
  fs.writeFileSync(
    path.join(dir, "init.luau"),
    'local Foo = require("@self/Foo")',
    "utf8",
  );
  fs.writeFileSync(
    path.join(tmp, "Bar.server.lua"),
    'local Baz = require("@self/Baz")',
    "utf8",
  );

  const project = {
    name: "SelfProj",
    tree: {
      $className: "DataModel",
      ReplicatedStorage: {
        MyModule: { $path: "modules/MyModule" },
        Bar: { $path: "Bar.server.lua" },
      },
    },
  };

  fs.writeFileSync(
    path.join(tmp, "default.project.json"),
    JSON.stringify(project, null, 2),
    "utf8",
  );

  const builder = new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  });
  const instances = await builder.build();

  const mod = instances.find((i) => i.name === "MyModule");
  assert.strictEqual(mod?.source, 'local Foo = require("./MyModule/Foo")');

  const script = instances.find((i) => i.name === "Bar");
  assert.strictEqual(script?.source, 'local Baz = require("./Bar/Baz")');

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder parses complex .model.json and normalizes properties", async () => {
  const tmp = makeTempDir();
  const models = path.join(tmp, "models");
  fs.mkdirSync(models, { recursive: true });

  const modelJson = `
{
  "Name": "TestSuite",
  "ClassName": "Model",
  "Children": [
    {
      "Name": "TestPart",
      "ClassName": "Part",
      "Properties": {
        "Size": { "Type": "Vector3", "Value": [4, 2, 1] },
        "Position": { "Type": "Vector3", "Value": [10, 5, 0] },
        "CFrame": { "Type": "CFrame", "Value": [10, 5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1] },
        "Color": { "Type": "Color3", "Value": [1, 0, 0] },
        "BrickColor": { "Type": "BrickColor", "Value": 1001 },
        "Shape": { "Type": "Enum", "Value": { "enumType": "PartType", "value": "Block" } },
        "Material": { "Type": "Enum", "Value": { "enumType": "Material", "value": "Plastic" } },
        "Anchored": true,
        "CanCollide": false,
        "Transparency": 0.25,
        "Reflectance": 0.1,
        "CustomPhysicalProperties": true,
        "CustomPhysicalProperties": {
          "Type": "PhysicalProperties",
          "Value": { "Density": 0.7, "Friction": 0.5, "Elasticity": 0.3, "FrictionWeight": 1, "ElasticityWeight": 1 }
        }
      }
    },
    {
      "Name": "TestAttachment",
      "ClassName": "Attachment",
      "Properties": {
        "CFrame": { "Type": "CFrame", "Value": [1, 2, 3, 0, 1, 0, -1, 0, 0, 0, 0, 1] },
        "Position": { "Type": "Vector3", "Value": [0.5, 1.5, 0] },
        "Axis": { "Type": "Vector3", "Value": [0, 1, 0] },
        "Visible": true
      }
    },
    {
      "Name": "TestLabel",
      "ClassName": "TextLabel",
      "Properties": {
        "Text": "Hello World",
        "FontFace": { "Type": "Font", "Value": { "family": "rbxasset://fonts/families/RobotoMono.json", "weight": "Thin", "style": "Normal" } },
        "TextColor3": { "Type": "Color3", "Value": [1, 1, 1] },
        "TextSize": 14,
        "RichText": true,
        "TextScaled": false,
        "TextWrapped": true,
        "Position": { "Type": "UDim2", "Value": [0, 10, 0, 20] },
        "Size": { "Type": "UDim2", "Value": [1, -20, 0, 30] },
        "BackgroundColor3": { "Type": "Color3", "Value": [0.2, 0.2, 0.2] },
        "BackgroundTransparency": 0.5,
        "ZIndex": 2,
        "LayoutOrder": 1,
        "AutoButtonColor": false
      }
    },
    {
      "Name": "TestParticles",
      "ClassName": "ParticleEmitter",
      "Properties": {
        "SpreadAngle": { "Type": "Vector2", "Value": [15, 30] },
        "Speed": { "Type": "NumberRange", "Value": [5, 10] },
        "Lifetime": { "Type": "NumberRange", "Value": [2, 4] },
        "Rate": 10,
        "Color": { "Type": "ColorSequence", "Value": [[0, 1, 0, 0], [1, 1, 1, 1]] },
        "Transparency": { "Type": "NumberSequence", "Value": [[0, 1], [1, 0]] },
        "Enabled": true,
        "LightEmission": 0.5,
        "LightInfluence": 0
      }
    },
    {
      "Name": "TestBeam",
      "ClassName": "Beam",
      "Properties": {
        "Color": { "Type": "ColorSequence", "Value": { "keypoints": [{ "time": 0, "value": [1, 0, 0] }, { "time": 1, "value": [0, 0, 1] }] } },
        "Transparency": { "Type": "NumberSequence", "Value": { "keypoints": [{ "time": 0, "value": 1, "envelope": 0 }, { "time": 1, "value": 0, "envelope": 0 }] } },
        "Width0": 0.5,
        "Width1": 1,
        "CurveSize0": 0,
        "CurveSize1": 0,
        "FaceCamera": true
      }
    },
    {
      "Name": "TestVectors",
      "ClassName": "Model",
      "Children": [
        {
          "Name": "Vec3Value",
          "ClassName": "Vector3Value",
          "Properties": {
            "Value": { "Type": "Vector3", "Value": [1, 2, 3] }
          }
        },
        {
          "Name": "ColorVal",
          "ClassName": "Color3Value",
          "Properties": {
            "Value": { "Type": "Color3", "Value": [0.5, 0.5, 0.5] }
          }
        }
      ]
    },
    {
      "Name": "TestValues",
      "ClassName": "Model",
      "Children": [
        {
          "Name": "NumVal",
          "ClassName": "NumberValue",
          "Properties": { "Value": 42.5 }
        },
        {
          "Name": "IntVal",
          "ClassName": "IntValue",
          "Properties": { "Value": { "Type": "Int32", "Value": 999 } }
        },
        {
          "Name": "BoolVal",
          "ClassName": "BoolValue",
          "Properties": { "Value": { "Type": "Bool", "Value": true } }
        },
        {
          "Name": "StrVal",
          "ClassName": "StringValue",
          "Properties": { "Value": { "Type": "String", "Value": "test string" } }
        }
      ]
    },
    {
      "Name": "SoundEffect",
      "ClassName": "Sound",
      "Properties": {
        "SoundId": { "Type": "ContentId", "Value": "rbxassetid://123456789" },
        "Volume": 0.8,
        "PlaybackSpeed": 1.5,
        "Looped": true,
        "RollOffMode": { "Type": "Enum", "Value": { "enumType": "RollOffMode", "value": "Inverse" } },
        "RollOffMinDistance": 10,
        "RollOffMaxDistance": 200
      }
    },
    {
      "Name": "TestScript",
      "ClassName": "Script",
      "Properties": {
        "Enabled": false,
        "RunContext": { "Type": "Enum", "Value": { "enumType": "RunContext", "value": "Legacy" } }
      }
    },
    {
      "Name": "TestTags",
      "ClassName": "Folder",
      "Tags": ["red", "blue", "green"]
    },
    {
      "Name": "ImplicitInference",
      "ClassName": "Model",
      "Properties": {},
      "Children": [
        {
          "Name": "ImplicitPart",
          "ClassName": "Part",
          "Properties": {
            "CFrame": [0, 10, 20, 1, 0, 0, 0, 1, 0, 0, 0, 1],
            "Size": [2, 2, 2],
            "Position": [5, 0, 5],
            "Color": [0, 1, 0],
            "Anchored": true,
            "Transparency": 0.5
          }
        },
        {
          "Name": "ImplicitLabel",
          "ClassName": "TextLabel",
          "Properties": {
            "Position": [0, 50, 0, 100],
            "Size": [0.5, 0, 0.5, 0],
            "Text": "Implicit",
            "TextColor3": [1, 1, 1],
            "BackgroundColor3": [0.1, 0.1, 0.1],
            "BackgroundTransparency": 0.3
          }
        },
        {
          "Name": "ImplicitEmitter",
          "ClassName": "ParticleEmitter",
          "Properties": {
            "SpreadAngle": [45, 60],
            "Color": [[0, 1, 0, 0, 0], [1, 1, 1, 1, 0]],
            "Transparency": [[0, 1], [1, 0]],
            "Speed": [5, 10],
            "Rate": 20
          }
        }
      ]
    },
    {
      "Name": "InstanceAttributes",
      "ClassName": "Part",
      "Attributes": {
        "Speed": 10,
        "DisplayName": "Runner",
        "IsActive": true,
        "SpawnPos": { "Type": "Vector3", "Value": [1, 2, 3] }
      },
      "Properties": {
        "Anchored": true,
        "Position": [0, 10, 0],
        "Color": [0, 0, 1]
      },
      "Tags": ["important", "test"]
    }
  ]
}
`;

  fs.writeFileSync(path.join(models, "test.model.json"), modelJson, "utf8");

  const project = {
    name: "ModelProj",
    tree: {
      $className: "DataModel",
      ReplicatedStorage: {
        Models: {
          TestSuite: { $path: "models/test.model.json" },
        },
      },
    },
  };

  fs.writeFileSync(
    path.join(tmp, "default.project.json"),
    JSON.stringify(project, null, 2),
    "utf8",
  );

  const builder = new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  });
  const instances = await builder.build();

  // A pod record is a single-key table whose key is the rbx-dom type name.
  const podTag = (value: unknown): string | undefined => {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return undefined;
    }
    const keys = Object.keys(value as Record<string, unknown>);
    return keys.length === 1 ? keys[0] : undefined;
  };
  const propsOf = (name: string): Record<string, any> =>
    (instances.find((i) => i.name === name)?.properties ?? {}) as Record<
      string,
      any
    >;

  const part = instances.find((i) => i.name === "TestPart");
  assert.ok(part, "TestPart emitted");
  assert.strictEqual(part?.className, "Part");
  assert.deepStrictEqual(propsOf("TestPart").Size, { Vector3: [4, 2, 1] });
  assert.strictEqual(part?.properties?.Anchored, true);
  // Explicit enums flatten to the item name, which Roblox coerces on assignment.
  assert.deepStrictEqual(propsOf("TestPart").Shape, { Enum: "Block" });

  const label = instances.find((i) => i.name === "TestLabel");
  assert.ok(label, "TestLabel emitted");
  assert.strictEqual(label?.properties?.Text, "Hello World");
  assert.strictEqual(podTag(propsOf("TestLabel").FontFace), "Font");

  const particles = instances.find((i) => i.name === "TestParticles");
  assert.ok(particles, "TestParticles emitted");
  assert.strictEqual(podTag(propsOf("TestParticles").Color), "ColorSequence");

  // Ambiguous values pass through untouched. The plugin resolves them, because
  // only the reflection database knows each property's declared type.
  const implicit = instances.find((i) => i.name === "ImplicitPart");
  assert.ok(implicit, "ImplicitPart emitted");
  assert.deepStrictEqual(
    propsOf("ImplicitPart").CFrame,
    [0, 10, 20, 1, 0, 0, 0, 1, 0, 0, 0, 1],
  );
  assert.deepStrictEqual(propsOf("ImplicitPart").Size, [2, 2, 2]);

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("globIgnorePaths ignore root-level files, not just nested ones", async () => {
  const tmp = makeTempDir();
  const src = path.join(tmp, "src");
  fs.mkdirSync(src, { recursive: true });

  fs.writeFileSync(path.join(src, "Kept.luau"), "return 1", "utf8");
  fs.writeFileSync(path.join(src, "Ignored.luau"), "return 2", "utf8");
  fs.writeFileSync(path.join(src, "nested.lock"), "x", "utf8");
  fs.mkdirSync(path.join(src, "deep"), { recursive: true });
  fs.writeFileSync(path.join(src, "deep", "Ignored.luau"), "return 3", "utf8");

  const project = {
    name: "IgnoreProj",
    tree: {
      $className: "DataModel",
      ReplicatedStorage: { $path: "src" },
    },
    globIgnorePaths: ["**/Ignored.luau"],
  };

  fs.writeFileSync(
    path.join(tmp, "default.project.json"),
    JSON.stringify(project, null, 2),
    "utf8",
  );

  const builder = new RojoSnapshotBuilder({
    cwd: tmp,
    projectFile: "default.project.json",
  });
  const instances = await builder.build();
  const names = instances.map((i) => i.path.join("/"));

  assert.ok(names.includes("ReplicatedStorage/Kept"), "unignored script kept");
  // `**/x` has to span zero directories: src/Ignored.luau sits one level under cwd
  assert.equal(names.includes("ReplicatedStorage/Ignored"), false);
  assert.equal(names.includes("ReplicatedStorage/deep/Ignored"), false);
  // A default pattern (`**/*.lock`) covers the same zero-or-more span
  assert.equal(names.includes("ReplicatedStorage/nested"), false);

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("RojoSnapshotBuilder pairs a script with its .model.json sibling regardless of readdir order", async () => {
  const tmp = makeTempDir();
  const src = path.join(tmp, "src");
  fs.mkdirSync(src, { recursive: true });
  // `Foo.luau` sorts before `Foo.model.json`, so the script is seen first
  fs.writeFileSync(path.join(src, "Foo.luau"), "return 1", "utf8");
  fs.writeFileSync(
    path.join(src, "Foo.model.json"),
    JSON.stringify({ ClassName: "Folder", Attributes: { Tagged: true } }),
    "utf8",
  );

  const instances = await new RojoSnapshotBuilder({ cwd: tmp }).buildLoose(
    src,
    ["ReplicatedStorage"],
  );

  const foo = instances.filter(
    (i) => i.path.join("/") === "ReplicatedStorage/Foo",
  );
  assert.strictEqual(foo.length, 1, "one instance at the path");
  assert.strictEqual(foo[0].className, "ModuleScript");
  assert.strictEqual(foo[0].source, "return 1");
  assert.deepStrictEqual(foo[0].attributes, { Tagged: true });

  fs.rmSync(tmp, { recursive: true, force: true });
});

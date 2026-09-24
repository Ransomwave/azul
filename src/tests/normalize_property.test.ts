import test from "node:test";
import assert from "node:assert/strict";

import { normalizeRojoProperty } from "../snapshot/rojo/normalizeProperty.js";

test("normalizeRojoProperty maps the explicit Rojo form onto a pod tag", () => {
  assert.deepStrictEqual(
    normalizeRojoProperty({ Type: "Vector3", Value: [4, 2, 1] }),
    { Vector3: [4, 2, 1] },
  );

  // Lowercase spelling is accepted the same way.
  assert.deepStrictEqual(
    normalizeRojoProperty({ type: "Color3", value: [1, 0, 0] }),
    { Color3: [1, 0, 0] },
  );

  // Payload shapes are carried through untouched; the plugin reshapes the ones
  // rbx-dom spells differently.
  assert.deepStrictEqual(
    normalizeRojoProperty({
      Type: "PhysicalProperties",
      Value: { Density: 0.7, Friction: 0.5 },
    }),
    { PhysicalProperties: { Density: 0.7, Friction: 0.5 } },
  );
});

test("normalizeRojoProperty flattens explicit enums to the item name", () => {
  // rbx-dom carries an enum as a name or number, both of which Roblox coerces
  // on assignment. The nested { enumType, value } form would decode to a table.
  assert.deepStrictEqual(
    normalizeRojoProperty({
      Type: "Enum",
      Value: { enumType: "PartType", value: "Block" },
    }),
    { Enum: "Block" },
  );

  assert.deepStrictEqual(
    normalizeRojoProperty({
      Type: "Enum",
      Value: { enumType: "Material", value: 288 },
    }),
    { Enum: 288 },
  );

  // An enum already given as a bare name or number is left alone.
  assert.deepStrictEqual(normalizeRojoProperty({ Type: "Enum", Value: 3 }), {
    Enum: 3,
  });
});

test("normalizeRojoProperty passes ambiguous values through untouched", () => {
  // Only the reflection database knows a property's declared type, so bare
  // values are resolved in the plugin rather than guessed at here.
  for (const value of [
    [4, 1.2, 2],
    [0, 50, 0, 100],
    [0, 10, 20, 1, 0, 0, 0, 1, 0, 0, 0, 1],
    "Hello",
    true,
    42,
    0.5,
  ]) {
    assert.deepStrictEqual(normalizeRojoProperty(value), value);
  }

  // An object that is not the explicit form is a payload, not a tagged value.
  const font = { family: "rbxasset://fonts/families/Arial.json", weight: 700 };
  assert.deepStrictEqual(normalizeRojoProperty(font), font);

  // An already fully qualified pod record is left as it is.
  assert.deepStrictEqual(normalizeRojoProperty({ Vector3: [1, 2, 3] }), {
    Vector3: [1, 2, 3],
  });
});

test("normalizeRojoProperty normalizes absent values to null", () => {
  assert.strictEqual(normalizeRojoProperty(null), null);
  assert.strictEqual(normalizeRojoProperty(undefined), null);
});

test("normalizeRojoProperty ignores partial explicit forms", () => {
  // Type without Value, or Value without Type, is not the explicit form.
  const typeOnly = { Type: "Vector3" };
  const valueOnly = { Value: [1, 2, 3] };
  assert.deepStrictEqual(normalizeRojoProperty(typeOnly), typeOnly);
  assert.deepStrictEqual(normalizeRojoProperty(valueOnly), valueOnly);
});

/**
 * Rojo project files carry property values in two shapes.
 *
 * The explicit shape, `{ "Type": "Vector3", "Value": [4, 1.2, 2] }`, maps
 * directly onto the rbx-dom pod shape `{ "Vector3": [4, 1.2, 2] }`.
 *
 * The ambiguous shape, a bare `[4, 1.2, 2]`, is the pod payload with its type
 * tag left off. Resolving it needs the property's declared type, so it is passed
 * through untouched and resolved in the plugin, where the reflection database
 * is already loaded.
 */
/**
 * Applies a pod type tag to an explicit value's payload.
 *
 * Most payloads already match what rbx-dom expects. Enums are the exception:
 * the explicit form nests `{ enumType, value }`, while pod carries the item's
 * name or numeric value directly, both of which Roblox coerces on assignment.
 */
function tagged(type: string, payload: unknown): unknown {
  if (
    type === "Enum" &&
    payload !== null &&
    typeof payload === "object" &&
    !Array.isArray(payload) &&
    "value" in payload
  ) {
    return { Enum: (payload as Record<string, unknown>).value };
  }

  return { [type]: payload };
}

export function normalizeRojoProperty(value: unknown): unknown {
  if (value === null || value === undefined) return null;

  if (typeof value === "object" && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;

    if (typeof record.Type === "string" && "Value" in record) {
      return tagged(record.Type, record.Value);
    }

    if (typeof record.type === "string" && "value" in record) {
      return tagged(record.type, record.value);
    }
  }

  return value;
}

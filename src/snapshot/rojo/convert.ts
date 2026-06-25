function convertExplicitRojoProperty(typeStr: string, value: any): any {
  const normalizedType = typeStr.toLowerCase();
  if (normalizedType === "vector3") {
    if (Array.isArray(value) && value.length === 3) {
      return { __type: "Vector3", x: value[0], y: value[1], z: value[2] };
    }
    if (typeof value === "object" && value !== null) {
      return {
        __type: "Vector3",
        x: value.x ?? value.X ?? 0,
        y: value.y ?? value.Y ?? 0,
        z: value.z ?? value.Z ?? 0,
      };
    }
  }
  if (normalizedType === "vector2") {
    if (Array.isArray(value) && value.length === 2) {
      return { __type: "Vector2", x: value[0], y: value[1] };
    }
    if (typeof value === "object" && value !== null) {
      return {
        __type: "Vector2",
        x: value.x ?? value.X ?? 0,
        y: value.y ?? value.Y ?? 0,
      };
    }
  }
  if (normalizedType === "vector2int16") {
    if (Array.isArray(value) && value.length === 2) {
      return { __type: "Vector2int16", x: value[0], y: value[1] };
    }
  }
  if (normalizedType === "vector3int16") {
    if (Array.isArray(value) && value.length === 3) {
      return { __type: "Vector3int16", x: value[0], y: value[1], z: value[2] };
    }
  }
  if (normalizedType === "color3") {
    if (Array.isArray(value) && value.length === 3) {
      return { __type: "Color3", r: value[0], g: value[1], b: value[2] };
    }
  }
  if (normalizedType === "color3uint8") {
    if (Array.isArray(value) && value.length === 3) {
      return { __type: "Color3uint8", r: value[0], g: value[1], b: value[2] };
    }
  }
  if (normalizedType === "cframe") {
    if (Array.isArray(value)) {
      return { __type: "CFrame", components: value };
    }
  }
  if (normalizedType === "udim") {
    if (Array.isArray(value) && value.length === 2) {
      return { __type: "UDim", scale: value[0], offset: value[1] };
    }
  }
  if (normalizedType === "udim2") {
    if (Array.isArray(value) && value.length === 4) {
      return {
        __type: "UDim2",
        xScale: value[0],
        xOffset: value[1],
        yScale: value[2],
        yOffset: value[3],
      };
    }
  }
  if (normalizedType === "brickcolor") {
    return {
      __type: "BrickColor",
      number: typeof value === "number" ? value : 0,
    };
  }
  if (normalizedType === "numberrange") {
    if (Array.isArray(value) && value.length === 2) {
      return { __type: "NumberRange", min: value[0], max: value[1] };
    }
  }
  if (normalizedType === "numbersequence") {
    if (Array.isArray(value)) {
      const keypoints = value.map((kp: any) => {
        if (Array.isArray(kp)) {
          return { time: kp[0], value: kp[1], envelope: kp[2] ?? 0 };
        }
        if (typeof kp === "object" && kp !== null) {
          return {
            time: kp.time ?? kp.Time ?? 0,
            value: kp.value ?? kp.Value ?? 0,
            envelope: kp.envelope ?? kp.Envelope ?? 0,
          };
        }
        return { time: 0, value: Number(kp), envelope: 0 };
      });
      return { __type: "NumberSequence", keypoints };
    }
  }
  if (normalizedType === "colorsequence") {
    if (Array.isArray(value)) {
      const keypoints = value.map((kp: any) => {
        if (Array.isArray(kp)) {
          return {
            time: kp[0],
            value: [kp[1], kp[2], kp[3]],
            envelope: kp[4] ?? 0,
          };
        }
        if (typeof kp === "object" && kp !== null) {
          const c = kp.value ?? kp.Value;
          const color = Array.isArray(c) ? c : [1, 1, 1];
          return {
            time: kp.time ?? kp.Time ?? 0,
            value: color,
            envelope: kp.envelope ?? kp.Envelope ?? 0,
          };
        }
        return { time: 0, value: [1, 1, 1], envelope: 0 };
      });
      return { __type: "ColorSequence", keypoints };
    }
  }
  if (normalizedType === "rect") {
    if (Array.isArray(value)) {
      if (value.length === 4) {
        return {
          __type: "Rect",
          minX: value[0],
          minY: value[1],
          maxX: value[2],
          maxY: value[3],
        };
      }
      if (
        value.length === 2 &&
        Array.isArray(value[0]) &&
        Array.isArray(value[1])
      ) {
        return {
          __type: "Rect",
          minX: value[0][0],
          minY: value[0][1],
          maxX: value[1][0],
          maxY: value[1][1],
        };
      }
    }
  }
  if (normalizedType === "physicalproperties") {
    if (typeof value === "object" && value !== null) {
      return {
        __type: "PhysicalProperties",
        density: value.Density ?? value.density ?? 0.7,
        friction: value.Friction ?? value.friction ?? 0.5,
        elasticity: value.Elasticity ?? value.elasticity ?? 0.3,
        frictionWeight: value.FrictionWeight ?? value.frictionWeight ?? 1.0,
        elasticityWeight:
          value.ElasticityWeight ?? value.elasticityWeight ?? 1.0,
      };
    }
  }
  if (normalizedType === "axes") {
    if (typeof value === "object" && value !== null) {
      return {
        __type: "Axes",
        x: value.X ?? value.x ?? true,
        y: value.Y ?? value.y ?? true,
        z: value.Z ?? value.z ?? true,
      };
    }
  }
  if (normalizedType === "faces") {
    if (typeof value === "object" && value !== null) {
      return {
        __type: "Faces",
        top: value.Top ?? value.top ?? false,
        bottom: value.Bottom ?? value.bottom ?? false,
        left: value.Left ?? value.left ?? false,
        right: value.Right ?? value.right ?? false,
        front: value.Front ?? value.front ?? false,
        back: value.Back ?? value.back ?? false,
      };
    }
  }
  if (normalizedType === "ray") {
    if (typeof value === "object" && value !== null) {
      const originValue = value.origin ?? value.Origin;
      const directionValue = value.direction ?? value.Direction;
      const origin = Array.isArray(originValue)
        ? {
            __type: "Vector3",
            x: originValue[0],
            y: originValue[1],
            z: originValue[2],
          }
        : { __type: "Vector3", x: 0, y: 0, z: 0 };
      const direction = Array.isArray(directionValue)
        ? {
            __type: "Vector3",
            x: directionValue[0],
            y: directionValue[1],
            z: directionValue[2],
          }
        : { __type: "Vector3", x: 0, y: 0, z: 1 };
      return { __type: "Ray", origin, direction };
    }
  }
  if (normalizedType === "region3") {
    if (typeof value === "object" && value !== null) {
      const min = value.min ?? value.Min;
      const max = value.max ?? value.Max;
      return {
        __type: "Region3",
        min: Array.isArray(min)
          ? { x: min[0], y: min[1], z: min[2] }
          : (min ?? { x: 0, y: 0, z: 0 }),
        max: Array.isArray(max)
          ? { x: max[0], y: max[1], z: max[2] }
          : (max ?? { x: 0, y: 0, z: 0 }),
      };
    }
  }
  if (normalizedType === "region3int16") {
    if (typeof value === "object" && value !== null) {
      const min = value.min ?? value.Min;
      const max = value.max ?? value.Max;
      return {
        __type: "Region3int16",
        min: Array.isArray(min)
          ? { x: min[0], y: min[1], z: min[2] }
          : (min ?? { x: 0, y: 0, z: 0 }),
        max: Array.isArray(max)
          ? { x: max[0], y: max[1], z: max[2] }
          : (max ?? { x: 0, y: 0, z: 0 }),
      };
    }
  }
  if (normalizedType === "font") {
    if (typeof value === "object" && value !== null) {
      return {
        __type: "Font",
        family: value.Family ?? value.family ?? "",
        weight: value.Weight ?? value.weight ?? "Regular",
        style: value.Style ?? value.style ?? "Normal",
      };
    }
  }
  if (normalizedType === "tags") {
    if (Array.isArray(value)) {
      return { __type: "Tags", tags: value.map(String) };
    }
  }
  if (normalizedType === "enum") {
    if (typeof value === "object" && value !== null) {
      const enumType =
        value.enumType || value.EnumType || value.Type || value.type;
      const enumValue = value.value || value.Value || value.name || value.Name;
      if (enumType && enumValue !== undefined) {
        return {
          __type: "Enum",
          enumType: String(enumType).replace(/^Enum\./, ""),
          value: enumValue,
        };
      }
    }
    return value;
  }
  return value;
}

export function convertImplicitRojoProperty(propName: string, val: any): any {
  if (val === null || val === undefined) {
    return null;
  }
  if (
    typeof val === "object" &&
    !Array.isArray(val) &&
    "Type" in val &&
    "Value" in val
  ) {
    return convertExplicitRojoProperty(val.Type, val.Value);
  }
  if (
    typeof val === "object" &&
    !Array.isArray(val) &&
    "type" in val &&
    "value" in val
  ) {
    return convertExplicitRojoProperty(val.type, val.value);
  }

  if (typeof val === "string") {
    return val;
  }

  if (typeof val === "boolean") {
    return val;
  }

  if (typeof val === "number") {
    return val;
  }

  if (Array.isArray(val)) {
    const allStrings = val.every((v) => typeof v === "string");
    if (allStrings && val.length > 0) {
      return { __type: "Tags", tags: val.map(String) };
    }

    const allNumbers = val.every((v) => typeof v === "number");
    if (allNumbers) {
      const lowerName = propName.toLowerCase();
      if (val.length === 12) {
        return { __type: "CFrame", components: val };
      }
      if (val.length === 3) {
        if (lowerName.includes("color")) {
          if (val.some((v) => v > 1.0)) {
            return { __type: "Color3uint8", r: val[0], g: val[1], b: val[2] };
          }
          return { __type: "Color3", r: val[0], g: val[1], b: val[2] };
        }
        return { __type: "Vector3", x: val[0], y: val[1], z: val[2] };
      }
      if (val.length === 2) {
        if (lowerName.includes("range")) {
          return { __type: "NumberRange", min: val[0], max: val[1] };
        }
        if (
          lowerName.includes("udim") ||
          lowerName.includes("size") ||
          lowerName.includes("position")
        ) {
          return { __type: "UDim", scale: val[0], offset: val[1] };
        }
        return { __type: "Vector2", x: val[0], y: val[1] };
      }
      if (val.length === 4) {
        if (lowerName.includes("rect")) {
          return {
            __type: "Rect",
            minX: val[0],
            minY: val[1],
            maxX: val[2],
            maxY: val[3],
          };
        }
        return {
          __type: "UDim2",
          xScale: val[0],
          xOffset: val[1],
          yScale: val[2],
          yOffset: val[3],
        };
      }
    }

    const allArraysOfTwo = val.every(
      (v: any) =>
        Array.isArray(v) &&
        v.length >= 2 &&
        v.every((n: any) => typeof n === "number"),
    );
    if (allArraysOfTwo && val.length > 0) {
      const sampleLen = val[0].length;
      if (sampleLen <= 3) {
        return {
          __type: "NumberSequence",
          keypoints: val.map((kp: any) => ({
            time: kp[0],
            value: kp[1],
            envelope: kp[2] ?? 0,
          })),
        };
      }
      if (sampleLen >= 4) {
        return {
          __type: "ColorSequence",
          keypoints: val.map((kp: any) => ({
            time: kp[0],
            value: [kp[1], kp[2], kp[3]],
            envelope: kp[4] ?? 0,
          })),
        };
      }
    }

    const allKeypointObjects = val.every(
      (v: any) =>
        typeof v === "object" &&
        v !== null &&
        !Array.isArray(v) &&
        ("time" in v || "Time" in v) &&
        ("value" in v || "Value" in v),
    );
    if (allKeypointObjects && val.length > 0) {
      const first = val[0];
      const colorVal = first.value ?? first.Value;
      if (Array.isArray(colorVal) && colorVal.length === 3) {
        return {
          __type: "ColorSequence",
          keypoints: val.map((kp: any) => {
            const resolvedValue = kp.value ?? kp.Value;

            return {
              time: kp.time ?? kp.Time ?? 0,
              value: Array.isArray(resolvedValue)
                ? [resolvedValue[0], resolvedValue[1], resolvedValue[2]]
                : [1, 1, 1],
              envelope: kp.envelope ?? kp.Envelope ?? 0,
            };
          }),
        };
      }
      return {
        __type: "NumberSequence",
        keypoints: val.map((kp: any) => ({
          time: kp.time ?? kp.Time ?? 0,
          value: kp.value ?? kp.Value ?? 0,
          envelope: kp.envelope ?? kp.Envelope ?? 0,
        })),
      };
    }
  }

  if (typeof val === "object" && val !== null) {
    if ("family" in val || "Family" in val) {
      return {
        __type: "Font",
        family: val.Family ?? val.family ?? "",
        weight: val.Weight ?? val.weight ?? "Regular",
        style: val.Style ?? val.style ?? "Normal",
      };
    }

    const copy: Record<string, any> = {};
    for (const [k, v] of Object.entries(val)) {
      copy[k] = convertImplicitRojoProperty(k, v);
    }
    return copy;
  }

  return val;
}

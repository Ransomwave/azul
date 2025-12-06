import { randomBytes } from "crypto";

/**
 * Generate a unique GUID for tracking instances
 */
export function generateGUID(): string {
  return randomBytes(16).toString("hex");
}

/**
 * Validate GUID format
 */
export function isValidGUID(guid: string): boolean {
  return /^[a-f0-9]{32}$/.test(guid);
}

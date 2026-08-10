/**
 * Reads required server-side configuration. Functions must never substitute
 * development credentials in production: a missing secret should make the
 * deployment/runtime fail loudly instead of issuing insecure tokens or sending
 * recordings to an unintended service.
 */
export function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(
      `Missing required server configuration: ${name}. ` +
        "Set it through Firebase/Google Cloud secret management before deploying."
    );
  }
  return value;
}

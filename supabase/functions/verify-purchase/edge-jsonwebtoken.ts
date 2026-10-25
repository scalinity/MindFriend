// Normalize Edge 1.77.8's EC curve alias on this key only. Keep JWT validation intact.
import jsonwebtoken from "npm:jsonwebtoken@9.0.3";
import { createPublicKey } from "node:crypto";
function verify(token: string, pem: string) {
  const key = createPublicKey(pem);
  const details = key.asymmetricKeyDetails;
  if (key.asymmetricKeyType === "ec" && details?.namedCurve === "p256" &&
      key.export({ format: "jwk" }).crv === "P-256") {
    Object.defineProperty(key, "asymmetricKeyDetails", {
      value: { ...details, namedCurve: "prime256v1" },
    });
  }
  return jsonwebtoken.verify(token, key);
}
export default { ...jsonwebtoken, verify };

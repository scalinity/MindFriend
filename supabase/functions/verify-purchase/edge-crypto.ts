// Edge 1.77.8 supports X509 parsing, publicKey, names, CA status and dates,
// but omits raw, infoAccess, verify and toString.
// Use the established certificate implementation already used by Apple's verifier.
// This subclass stays local to apple-verifier.js; no global prototypes are changed.
import { X509Certificate as NativeX509Certificate } from "node:crypto";
import type { KeyObject } from "node:crypto";
import { Buffer } from "node:buffer";
import jsrsasign from "npm:jsrsasign@11.1.5";

export { createHash, verify } from "node:crypto";

export class X509Certificate extends NativeX509Certificate {
  private readonly parsed: InstanceType<typeof jsrsasign.X509>;
  private readonly pem: string;

  constructor(input: string | Buffer) {
    super(input);
    this.parsed = new jsrsasign.X509();
    this.parsed.readCertHex(
      typeof input === "string" ? jsrsasign.pemtohex(input) : input.toString("hex"),
    );
    this.pem = jsrsasign.hextopem(this.parsed.hex, "CERTIFICATE");
    Object.defineProperties(this, {
      raw: { value: Buffer.from(this.parsed.hex, "hex") },
      infoAccess: {
        value: this.parsed.getExtAIAInfo()?.ocsp?.map((uri) => `OCSP - URI:${uri}`)
          .join("\n"),
      },
    });
  }

  override toString(): string {
    return this.pem;
  }

  override verify(publicKey: KeyObject): boolean {
    return this.parsed.verifySignature(
      publicKey.export({ type: "spki", format: "pem" }) as string,
    );
  }
}

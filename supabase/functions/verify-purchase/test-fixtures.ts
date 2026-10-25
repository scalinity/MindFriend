// Original synthetic fixtures. Keys are generated per run in ignored scratch,
// never stored in the repository; these are not Apple certificates or purchases.
import { Buffer } from "node:buffer";
const testNow = Date.now();
Object.defineProperty(Date, "now", { value: () => testNow, configurable: true });
import { sign, X509Certificate } from "node:crypto";

// Real OCSP HTTP transport stays on loopback; no external network is allowed.
const ocspResponses = new Map<string, Buffer>();
let ocspAvailable = true;
let ocspRevoked = false;
export function setOCSPRevoked(value: boolean) { ocspRevoked = value; }
export function setOCSPAvailable(value: boolean) {
  ocspAvailable = value;
}
export const ocspServer = { shutdown: async () => {
  await Deno.writeTextFile(".cache/issue17-runtime/fixture-data.json", JSON.stringify({
    now: testNow,
    chains: Object.fromEntries(chains.map((chain) => [chain.prefix, {
      root: chain.root.toString("base64"),
      certificates: chain.certificates,
      ocsp: Object.fromEntries([...chain.ocsp].map(([url, der]) => [url, der.toString("base64")])),
      revokedOcsp: Object.fromEntries([...chain.revokedOcsp].map(([url, der]) => [url, der.toString("base64")])),
      vectors: Object.fromEntries(chain.vectors),
    }])),
  }, null, 2));
} };
const ocspBase = "https://ocsp.synthetic.invalid";
export function getOCSPResponse(url: string) {
  return ocspAvailable ? (ocspRevoked ? trustedChain.revokedOcsp.get(url) : ocspResponses.get(new URL(url).pathname)) : undefined;
}

await Deno.mkdir(".cache/issue17-runtime/generated", { recursive: true });
const directory = await Deno.makeTempDir({
  dir: ".cache/issue17-runtime/generated",
  prefix: "certificates-",
});

async function openssl(...args: string[]) {
  const result = await new Deno.Command("openssl", {
    cwd: directory,
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
  return new TextDecoder().decode(result.stdout).trim();
}

async function generateChain(prefix: string, leafDays = 2, leafOID = true, intermediateCA = true) {
  for (const name of ["root", "intermediate", "leaf"]) {
    await openssl(
      "ecparam",
      "-name",
      name === "leaf" ? "prime256v1" : "secp384r1",
      "-genkey",
      "-noout",
      "-out",
      `${prefix}-${name}.key`,
    );
    await openssl(
      "req",
      "-new",
      "-key",
      `${prefix}-${name}.key`,
      "-subj",
      `/CN=Synthetic ${prefix} ${name}`,
      "-out",
      `${prefix}-${name}.csr`,
    );
  }
  await openssl(
    "req",
    "-x509",
    "-new",
    "-key",
    `${prefix}-root.key`,
    "-subj",
    `/CN=Synthetic ${prefix} root`,
    "-days",
    "2",
    "-sha384",
    "-addext",
    "basicConstraints=critical,CA:TRUE",
    "-addext",
    "keyUsage=critical,keyCertSign,cRLSign",
    "-out",
    `${prefix}-root.pem`,
  );

  await Deno.writeTextFile(
    `${directory}/intermediate.ext`,
    [
      `basicConstraints=critical,CA:${intermediateCA ? "TRUE,pathlen:0" : "FALSE"}`,
      "keyUsage=critical,keyCertSign,cRLSign,digitalSignature",
      "subjectKeyIdentifier=hash",
      "authorityKeyIdentifier=keyid,issuer",
      `authorityInfoAccess=OCSP;URI:${ocspBase}/intermediate`,
      "1.2.840.113635.100.6.2.1=DER:05:00",
    ].join("\n"),
  );
  await openssl(
    "x509",
    "-req",
    "-in",
    `${prefix}-intermediate.csr`,
    "-CA",
    `${prefix}-root.pem`,
    "-CAkey",
    `${prefix}-root.key`,
    "-set_serial",
    "2",
    "-days",
    "2",
    "-sha384",
    "-extfile",
    "intermediate.ext",
    "-out",
    `${prefix}-intermediate.pem`,
  );

  await Deno.writeTextFile(
    `${directory}/leaf.ext`,
    [
      "basicConstraints=critical,CA:FALSE",
      "keyUsage=critical,digitalSignature",
      "subjectKeyIdentifier=hash",
      "authorityKeyIdentifier=keyid,issuer",
      `authorityInfoAccess=OCSP;URI:${ocspBase}/leaf`,
      ...(leafOID ? ["1.2.840.113635.100.6.11.1=DER:05:00"] : []),
    ].join("\n"),
  );
  await openssl(
    "x509",
    "-req",
    "-in",
    `${prefix}-leaf.csr`,
    "-CA",
    `${prefix}-intermediate.pem`,
    "-CAkey",
    `${prefix}-intermediate.key`,
    "-set_serial",
    "3",
    "-days",
    "2",
    "-sha384",
    "-extfile",
    "leaf.ext",
    "-out",
    `${prefix}-leaf.pem`,
  );

  if (leafDays < 0) {
    await Deno.writeTextFile(`${directory}/expired-ca.conf`, `[ca]\ndefault_ca=issuer\n[issuer]\ndatabase=expired-ca.index\nnew_certs_dir=.\nserial=expired-ca.serial\ndefault_md=sha256\npolicy=names\n[names]\ncommonName=supplied\n`);
    await Deno.writeTextFile(`${directory}/expired-ca.index`, "");
    await Deno.writeTextFile(`${directory}/expired-ca.serial`, "03\n");
    const asTime = (offset: number) => new Date(testNow + offset).toISOString().slice(0,19).replace(/[-:T]/g, "") + "Z";
    await openssl("ca", "-batch", "-notext", "-config", "expired-ca.conf",
      "-cert", `${prefix}-intermediate.pem`, "-keyfile", `${prefix}-intermediate.key`,
      "-in", `${prefix}-leaf.csr`, "-out", `${prefix}-leaf.pem`, "-extfile", "leaf.ext",
      "-startdate", asTime(-172800000), "-enddate", asTime(-86400000));
  }

  const [rootPem, intermediatePem, leafPem, leafKey] = await Promise.all(
    ["root.pem", "intermediate.pem", "leaf.pem", "leaf.key"].map((name) =>
      Deno.readTextFile(`${directory}/${prefix}-${name}`)
    ),
  );
  const certificates = [leafPem, intermediatePem, rootPem].map((pem) =>
    new X509Certificate(pem)
  );

  const ocsp = new Map<string, Buffer>();
  const revokedOcsp = new Map<string, Buffer>();
  const vectors = new Map<string, string>();
  for (
    const [name, issuer, serial] of [["leaf", "intermediate", "03"], [
      "intermediate",
      "root",
      "02",
    ]]
  ) {
    const expiry =
      new Date(certificates[name === "leaf" ? 0 : 1].validTo).toISOString()
        .slice(2, 19).replace(/[-:T]/g, "") + "Z";
    await Deno.writeTextFile(
      `${directory}/${prefix}-${name}.index`,
      `V\t${expiry}\t\t${serial}\tunknown\t/CN=Synthetic ${prefix} ${name}\n`,
    );
    // Delegate OCSP signing to a responder with the required extended key usage.
    await openssl(
      "ecparam",
      "-name",
      "prime256v1",
      "-genkey",
      "-noout",
      "-out",
      `${prefix}-${name}-ocsp.key`,
    );
    await openssl(
      "req",
      "-new",
      "-key",
      `${prefix}-${name}-ocsp.key`,
      "-subj",
      `/CN=Synthetic ${prefix} ${name} OCSP`,
      "-out",
      `${prefix}-${name}-ocsp.csr`,
    );
    await Deno.writeTextFile(
      `${directory}/ocsp.ext`,
      "basicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,OCSPSigning\n",
    );
    await openssl(
      "x509",
      "-req",
      "-in",
      `${prefix}-${name}-ocsp.csr`,
      "-CA",
      `${prefix}-${issuer}.pem`,
      "-CAkey",
      `${prefix}-${issuer}.key`,
      "-set_serial",
      name === "leaf" ? "4" : "5",
      "-days",
      "2",
      "-sha256",
      "-extfile",
      "ocsp.ext",
      "-out",
      `${prefix}-${name}-ocsp.pem`,
    );
    await openssl(
      "ocsp",
      "-index",
      `${prefix}-${name}.index`,
      "-rsigner",
      `${prefix}-${name}-ocsp.pem`,
      "-rkey",
      `${prefix}-${name}-ocsp.key`,
      "-CA",
      `${prefix}-${issuer}.pem`,
      "-sha256",
      "-issuer",
      `${prefix}-${issuer}.pem`,
      "-cert",
      `${prefix}-${name}.pem`,
      "-respout",
      `${prefix}-${name}.ocsp`,
      "-ndays",
      "1",
    );
    ocsp.set(
      `${ocspBase}/${name}`,
      Buffer.from(await Deno.readFile(`${directory}/${prefix}-${name}.ocsp`)),
    );
    if (prefix === "trusted") {
      ocspResponses.set(`/${name}`, ocsp.get(`${ocspBase}/${name}`)!);
    }
    await Deno.writeTextFile(`${directory}/${prefix}-${name}.revoked.index`,
      `R\t${expiry}\t${new Date(testNow - 60000).toISOString().slice(2, 19).replace(/[-:T]/g, "")}Z\t${serial}\tunknown\t/CN=Synthetic ${prefix} ${name}\n`);
    await openssl("ocsp", "-index", `${prefix}-${name}.revoked.index`,
      "-rsigner", `${prefix}-${name}-ocsp.pem`, "-rkey", `${prefix}-${name}-ocsp.key`,
      "-CA", `${prefix}-${issuer}.pem`, "-sha256", "-issuer", `${prefix}-${issuer}.pem`,
      "-cert", `${prefix}-${name}.pem`, "-respout", `${prefix}-${name}.revoked.ocsp`, "-ndays", "1");
    revokedOcsp.set(`${ocspBase}/${name}`, Buffer.from(await Deno.readFile(`${directory}/${prefix}-${name}.revoked.ocsp`)));
  }

  return {
    prefix,
    root: certificates[2].raw,
    certificates: certificates.map((cert) => cert.raw.toString("base64")),
    ocsp,
    revokedOcsp,
    vectors,
    sign(payload: Record<string, unknown>) {
      const header = Buffer.from(
        JSON.stringify({
          alg: "ES256",
          x5c: certificates.map((certificate) =>
            certificate.raw.toString("base64")
          ),
        }),
      ).toString("base64url");
      const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
      const input = `${header}.${body}`;
      const signed = `${input}.${
        sign("sha256", Buffer.from(input), {
          key: leafKey,
          dsaEncoding: "ieee-p1363",
        }).toString("base64url")
      }`;
      vectors.set(JSON.stringify(payload), signed);
      return signed;
    },
  };
}

const chains = await (async () => {
  try {
    return [
      await generateChain("trusted"),
      await generateChain("untrusted"),
      await generateChain("expired", -1),
      await generateChain("missing-oid", 2, false),
      await generateChain("non-ca", 2, true, false),
    ] as const;
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
})();
export const [trustedChain, untrustedChain, expiredChain, missingOIDChain, nonCAChain] = chains;
// Signing keys are now only in this test process's closures.

export const testTransaction = (overrides: Record<string, unknown> = {}) => ({
  transactionId: "200000000000001",
  originalTransactionId: "100000000000001",
  bundleId: "com.mindfriend.app",
  productId: "com.mindfriend.premium.monthly",
  purchaseDate: Date.now() - 60_000,
  originalPurchaseDate: Date.now() - 31 * 86_400_000,
  expiresDate: Date.now() + 86_400_000,
  quantity: 1,
  type: "Auto-Renewable Subscription",
  inAppOwnershipType: "PURCHASED",
  signedDate: Date.now(),
  environment: "Production",
  ...overrides,
});

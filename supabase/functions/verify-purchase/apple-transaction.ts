// @deno-types="npm:@apple/app-store-server-library@3.1.0/dist/jws_verification.d.ts"
import { SignedDataVerifier, VerificationException, VerificationStatus } from "./apple-verifier.js";
import {
  Environment,
  type JWSTransactionDecodedPayload,
} from "npm:@apple/app-store-server-library@3.1.0";
import { Buffer } from "node:buffer";
import { VALID_PRODUCT_IDS } from "../_shared/billing-types.ts";
import { APPLE_ROOT_CERTIFICATES } from "./apple-roots.ts";

const BUNDLE_ID = "com.mindfriend.app";
const APP_APPLE_ID = 6758198271;
const roots = APPLE_ROOT_CERTIFICATES.map((root) =>
  Buffer.from(root, "base64")
);

// Only Apple-signed Production/Sandbox data is accepted. Online certificate
// revocation checks stay enabled; request fields never select a trust policy.
const verifiers = [
  ["Production", new SignedDataVerifier(
    roots,
    true,
    Environment.PRODUCTION,
    BUNDLE_ID,
    APP_APPLE_ID,
  )],
  ["Sandbox", new SignedDataVerifier(
    roots,
    true,
    Environment.SANDBOX,
    BUNDLE_ID,
    APP_APPLE_ID,
  )],
] as const;

export class TransactionVerificationError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly revokedTransaction?: { transactionId: string; originalTransactionId: string },
    public readonly verifiers?: VerifierFailure[],
  ) {
    super(message);
    this.name = "TransactionVerificationError";
  }
}

// Why each verifier refused the JWS: Apple's status, the source line that threw
// and the underlying error. Never includes the signed transaction or its claims.
export type VerifierFailure = {
  environment: string;
  status?: number;
  at?: string;
  cause?: string;
};

function sourceLine(error: unknown) {
  return (error as Error | undefined)?.stack?.split("\n").slice(1)
    .map((frame) => /([\w.-]+\.[jt]s):(\d+)/.exec(frame))
    .find(Boolean)?.slice(1).join(":");
}

function describeFailure(environment: string, error: unknown): VerifierFailure {
  const cause = error instanceof VerificationException ? error.cause : error;
  return {
    environment,
    status: error instanceof VerificationException ? error.status : undefined,
    at: sourceLine(error),
    cause: cause instanceof Error
      ? `${cause.name}: ${cause.message}`.slice(0, 160) + ` @ ${sourceLine(cause)}`
      : undefined,
  };
}

export type VerifiedAppleTransaction = JWSTransactionDecodedPayload & {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  expiresDate: number;
};

export async function verifyAppleTransaction(
  signedTransaction: string,
  callerId: string,
): Promise<VerifiedAppleTransaction> {
  let transaction: JWSTransactionDecodedPayload | undefined;
  let retryable = false;
  const failures: VerifierFailure[] = [];
  if (typeof signedTransaction === "string") {
    for (const [environment, verifier] of verifiers) {
      try {
        transaction = await verifier.verifyAndDecodeTransaction(
          signedTransaction,
        );
        break;
      } catch (error) {
        if (
          error instanceof VerificationException &&
          error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
        ) retryable = true;
        // Both verifiers enforce the same roots, signatures and online checks;
        // only the expected, cryptographically verified environment differs.
        failures.push(describeFailure(environment, error));
      }
    }
  }
  if (!transaction) {
    throw new TransactionVerificationError(
      retryable ? "VERIFICATION_UNAVAILABLE" : "JWS_VERIFICATION_FAILED",
      retryable
        ? "Purchase verification is temporarily unavailable. Try Restore Purchases."
        : "Invalid transaction signature",
      undefined,
      failures,
    );
  }

  if (
    !transaction.productId || !VALID_PRODUCT_IDS.includes(transaction.productId)
  ) {
    throw new TransactionVerificationError(
      "INVALID_PRODUCT_ID",
      "Invalid product ID in transaction",
    );
  }
  if (
    !transaction.transactionId?.trim() ||
    !transaction.originalTransactionId?.trim()
  ) {
    throw new TransactionVerificationError(
      "INVALID_TRANSACTION_ID",
      "Missing transaction identifiers",
    );
  }
  // Purchases made before account tokens were supplied remain restorable. When
  // Apple includes a token, it must bind the purchase to the authenticated UUID.
  if (
    transaction.appAccountToken !== undefined &&
    transaction.appAccountToken.toLowerCase() !== callerId.toLowerCase()
  ) {
    throw new TransactionVerificationError(
      "APP_ACCOUNT_TOKEN_MISMATCH",
      "Purchase belongs to another account",
    );
  }
  if (
    transaction.revocationDate !== undefined ||
    transaction.revocationReason !== undefined
  ) {
    throw new TransactionVerificationError(
      "TRANSACTION_REVOKED",
      "Transaction has been revoked",
      { transactionId: transaction.transactionId, originalTransactionId: transaction.originalTransactionId },
    );
  }
  // Every supported product is a subscription. Never manufacture a new expiry
  // for an old signed purchase that omits Apple's subscription expiry.
  if (
    !Number.isSafeInteger(transaction.expiresDate) ||
    !Number.isFinite(new Date(transaction.expiresDate!).getTime())
  ) {
    throw new TransactionVerificationError(
      "INVALID_TRANSACTION_EXPIRY",
      "Missing or invalid subscription expiry",
    );
  }
  if (transaction.expiresDate! <= Date.now()) {
    throw new TransactionVerificationError(
      "TRANSACTION_EXPIRED",
      "Subscription has expired",
    );
  }


  return transaction as VerifiedAppleTransaction;
}

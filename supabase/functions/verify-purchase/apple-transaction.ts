import {
  Environment,
  type JWSTransactionDecodedPayload,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
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
  new SignedDataVerifier(
    roots,
    true,
    Environment.PRODUCTION,
    BUNDLE_ID,
    APP_APPLE_ID,
  ),
  new SignedDataVerifier(
    roots,
    true,
    Environment.SANDBOX,
    BUNDLE_ID,
    APP_APPLE_ID,
  ),
];

export class TransactionVerificationError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
    this.name = "TransactionVerificationError";
  }
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
  if (typeof signedTransaction === "string") {
    for (const verifier of verifiers) {
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
      }
    }
  }
  if (!transaction) {
    throw new TransactionVerificationError(
      retryable ? "VERIFICATION_UNAVAILABLE" : "JWS_VERIFICATION_FAILED",
      retryable
        ? "Purchase verification is temporarily unavailable. Try Restore Purchases."
        : "Invalid transaction signature",
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
  if (
    transaction.revocationDate !== undefined ||
    transaction.revocationReason !== undefined
  ) {
    throw new TransactionVerificationError(
      "TRANSACTION_REVOKED",
      "Transaction has been revoked",
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

  return transaction as VerifiedAppleTransaction;
}

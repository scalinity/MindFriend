/*
Copyright 2023 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
// Copyright (c) 2023 Apple Inc. Licensed under MIT License (APPLE-LICENSE.txt).
// Vendored from @apple/app-store-server-library 3.1.0 dist/jws_verification.js.
// Only the module format/imports and export declarations differ from upstream.
// The local crypto adapter supplies X509 methods missing from Edge 1.77.8.
import { Buffer } from "node:buffer";
import jsonwebtoken from "./edge-jsonwebtoken.ts";
import * as base64url_1 from "npm:base64url@3.0.1";
import * as crypto_1 from "./edge-crypto.ts";
import jsrsasign_1 from "npm:jsrsasign@11.1.5";
import nodeFetch, { Headers } from "npm:node-fetch@2.7.0";
const node_fetch_1 = { default: nodeFetch, Headers };
import * as Environment_1 from "npm:@apple/app-store-server-library@3.1.0/dist/models/Environment.js";
import * as JWSTransactionDecodedPayload_1 from "npm:@apple/app-store-server-library@3.1.0/dist/models/JWSTransactionDecodedPayload.js";
import * as ResponseBodyV2DecodedPayload_1 from "npm:@apple/app-store-server-library@3.1.0/dist/models/ResponseBodyV2DecodedPayload.js";
import * as JWSRenewalInfoDecodedPayload_1 from "npm:@apple/app-store-server-library@3.1.0/dist/models/JWSRenewalInfoDecodedPayload.js";
import * as DecodedRealtimeRequestBody_1 from "npm:@apple/app-store-server-library@3.1.0/dist/models/DecodedRealtimeRequestBody.js";
import * as AppTransaction_1 from "npm:@apple/app-store-server-library@3.1.0/dist/models/AppTransaction.js";
const MAX_SKEW = 60000;
const MAXIMUM_CACHE_SIZE = 32; // There are unlikely to be more than a couple keys at once
const CACHE_TIME_LIMIT = 15 * 60 * 1000; // 15 minutes
class CacheValue {
    constructor(publicKey, cacheExpiry) {
        this.publicKey = publicKey;
        this.cacheExpiry = cacheExpiry;
    }
}
/**
 * A class providing utility methods for verifying and decoding App Store signed data.
 *
 * Example Usage:
 * ```ts
 * const verifier = new SignedDataVerifier([appleRoot, appleRoot2], true, Environment.SANDBOX, "com.example")
 *
 * try {
 *     const decodedNotification = verifier.verifyAndDecodeNotification("ey...")
 *     console.log(decodedNotification)
 * } catch (e) {
 *     console.error(e)
 * }
 * ```
 */
export class SignedDataVerifier {
    /**
     *
     * @param appleRootCertificates A list of DER-encoded root certificates
     * @param enableOnlineChecks Whether to enable revocation checking and check expiration using the current date
     * @param environment The App Store environment to target for checks
     * @param bundleId The app's bundle identifier
     * @param appAppleId The app's identifier, omitted in the sandbox environment
     */
    constructor(appleRootCertificates, enableOnlineChecks, environment, bundleId, appAppleId) {
        this.JWSRenewalInfoDecodedPayloadValidator = new JWSRenewalInfoDecodedPayload_1.JWSRenewalInfoDecodedPayloadValidator();
        this.JWSTransactionDecodedPayloadValidator = new JWSTransactionDecodedPayload_1.JWSTransactionDecodedPayloadValidator();
        this.responseBodyV2DecodedPayloadValidator = new ResponseBodyV2DecodedPayload_1.ResponseBodyV2DecodedPayloadValidator();
        this.appTransactionValidator = new AppTransaction_1.AppTransactionValidator();
        this.decodedRealtimeRequestBodyValidator = new DecodedRealtimeRequestBody_1.DecodedRealtimeRequestBodyValidator();
        this.rootCertificates = appleRootCertificates.map(cert => new crypto_1.X509Certificate(cert));
        this.enableOnlineChecks = enableOnlineChecks;
        this.bundleId = bundleId;
        this.environment = environment;
        this.appAppleId = appAppleId;
        this.verifiedPublicKeyCache = {};
        if (environment === Environment_1.Environment.PRODUCTION && appAppleId === undefined) {
            throw new Error("appAppleId is required when the environment is Production");
        }
    }
    /**
     * Verifies and decodes a signedTransaction obtained from the App Store Server API, an App Store Server Notification, or from a device
     * See {@link https://developer.apple.com/documentation/appstoreserverapi/jwstransaction JWSTransaction}
     *
     * @param signedTransaction The signedTransaction field
     * @return The decoded transaction info after verification
     * @throws VerificationException Thrown if the data could not be verified
     */
    async verifyAndDecodeTransaction(signedTransactionInfo) {
        const decodedJWT = await this.verifyJWT(signedTransactionInfo, this.JWSTransactionDecodedPayloadValidator, this.extractSignedDate);
        if (decodedJWT.bundleId !== this.bundleId) {
            throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER);
        }
        if (decodedJWT.environment !== this.environment) {
            throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
        }
        return decodedJWT;
    }
    /**
     * Verifies and decodes a signedRenewalInfo obtained from the App Store Server API, an App Store Server Notification, or from a device
     * See {@link https://developer.apple.com/documentation/appstoreserverapi/jwsrenewalinfo JWSRenewalInfo}
     *
     * @param signedRenewalInfo The signedRenewalInfo field
     * @return The decoded renewal info after verification
     * @throws VerificationException Thrown if the data could not be verified
     */
    async verifyAndDecodeRenewalInfo(signedRenewalInfo) {
        const decodedRenewalInfo = await this.verifyJWT(signedRenewalInfo, this.JWSRenewalInfoDecodedPayloadValidator, this.extractSignedDate);
        const environment = decodedRenewalInfo.environment;
        if (this.environment !== environment) {
            throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
        }
        return decodedRenewalInfo;
    }
    /**
     * Verifies and decodes an App Store Server Notification signedPayload
     * See {@link https://developer.apple.com/documentation/appstoreservernotifications/signedpayload signedPayload}
     *
     * @param signedPayload The payload received by your server
     * @return The decoded payload after verification
     * @throws VerificationException Thrown if the data could not be verified
     */
    async verifyAndDecodeNotification(signedPayload) {
        const decodedJWT = await this.verifyJWT(signedPayload, this.responseBodyV2DecodedPayloadValidator, this.extractSignedDate);
        let appAppleId;
        let bundleId;
        let environment;
        if (decodedJWT.data) {
            appAppleId = decodedJWT.data.appAppleId;
            bundleId = decodedJWT.data.bundleId;
            environment = decodedJWT.data.environment;
        }
        else if (decodedJWT.summary) {
            appAppleId = decodedJWT.summary.appAppleId;
            bundleId = decodedJWT.summary.bundleId;
            environment = decodedJWT.summary.environment;
        }
        else if (decodedJWT.externalPurchaseToken) {
            appAppleId = decodedJWT.externalPurchaseToken.appAppleId;
            bundleId = decodedJWT.externalPurchaseToken.bundleId;
            if (decodedJWT.externalPurchaseToken.externalPurchaseId && decodedJWT.externalPurchaseToken.externalPurchaseId.startsWith("SANDBOX")) {
                environment = Environment_1.Environment.SANDBOX;
            }
            else {
                environment = Environment_1.Environment.PRODUCTION;
            }
        }
        else if (decodedJWT.appData) {
            appAppleId = decodedJWT.appData.appAppleId;
            bundleId = decodedJWT.appData.bundleId;
            environment = decodedJWT.appData.environment;
        }
        this.verifyNotification(bundleId, appAppleId, environment);
        return decodedJWT;
    }
    verifyNotification(bundleId, appAppleId, environment) {
        if (this.bundleId !== bundleId || (this.environment === Environment_1.Environment.PRODUCTION && this.appAppleId !== appAppleId)) {
            throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER);
        }
        if (this.environment !== environment) {
            throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
        }
    }
    /**
     * Verifies and decodes a signed AppTransaction
     * See {@link https://developer.apple.com/documentation/storekit/apptransaction AppTransaction}
     *
     * @param signedAppTransaction The signed AppTransaction
     * @returns The decoded AppTransaction after validation
     * @throws VerificationException Thrown if the data could not be verified
     */
    async verifyAndDecodeAppTransaction(signedAppTransaction) {
        const decodedAppTransaction = await this.verifyJWT(signedAppTransaction, this.appTransactionValidator, t => t.receiptCreationDate === undefined ? new Date() : new Date(t.receiptCreationDate));
        const environment = decodedAppTransaction.receiptType;
        if (this.bundleId !== decodedAppTransaction.bundleId || (this.environment === Environment_1.Environment.PRODUCTION && this.appAppleId !== decodedAppTransaction.appAppleId)) {
            throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER);
        }
        if (this.environment !== environment) {
            throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
        }
        return decodedAppTransaction;
    }
    /**
     * Verifies and decodes a Retention Messaging API signedPayload
     * See {@link https://developer.apple.com/documentation/retentionmessaging/signedpayload signedPayload}
     *
     * @param signedPayload The payload received by your server
     * @returns The decoded payload after verification
     * @throws VerificationException Thrown if the data could not be verified
     */
    async verifyAndDecodeRealtimeRequest(signedPayload) {
        const decodedRequest = await this.verifyJWT(signedPayload, this.decodedRealtimeRequestBodyValidator, this.extractSignedDate);
        if (this.environment === Environment_1.Environment.PRODUCTION && this.appAppleId !== decodedRequest.appAppleId) {
            throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER);
        }
        if (this.environment !== decodedRequest.environment) {
            throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
        }
        return decodedRequest;
    }
    async verifyJWT(jwt, validator, signedDateExtractor) {
        let certificateChain;
        let decodedJWT;
        try {
            decodedJWT = jsonwebtoken.decode(jwt);
            if (!validator.validate(decodedJWT)) {
                throw new VerificationException(VerificationStatus.FAILURE);
            }
            if (this.environment === Environment_1.Environment.XCODE || this.environment === Environment_1.Environment.LOCAL_TESTING) {
                // Data is not signed by the App Store, and verification should be skipped
                // The environment MUST be checked in the public method calling this
                return decodedJWT;
            }
            try {
                const header = jwt.split('.')[0];
                const decodedHeader = base64url_1.default.decode(header);
                const headerObj = JSON.parse(decodedHeader);
                const chain = headerObj['x5c'] ?? [];
                if (chain.length != 3) {
                    throw new VerificationException(VerificationStatus.INVALID_CHAIN_LENGTH);
                }
                certificateChain = chain.slice(0, 2).map(cert => new crypto_1.X509Certificate(Buffer.from(cert, 'base64')));
            }
            catch (error) {
                if (error instanceof Error) {
                    throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE, error);
                }
                throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE);
            }
            const effectiveDate = this.enableOnlineChecks ? new Date() : signedDateExtractor(decodedJWT);
            const publicKey = await this.verifyCertificateChain(this.rootCertificates, certificateChain[0], certificateChain[1], effectiveDate);
            const encodedKey = publicKey.export({
                type: "spki",
                format: "pem"
            });
            jsonwebtoken.verify(jwt, encodedKey);
            return decodedJWT;
        }
        catch (error) {
            if (error instanceof VerificationException) {
                throw error;
            }
            else if (error instanceof Error) {
                throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE, error);
            }
            throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
        }
    }
    async verifyCertificateChain(trustedRoots, leaf, intermediate, effectiveDate) {
        let cacheKey = leaf.toString() + intermediate.toString();
        if (this.enableOnlineChecks) {
            if (cacheKey in this.verifiedPublicKeyCache) {
                if (this.verifiedPublicKeyCache[cacheKey].cacheExpiry > new Date().getTime()) {
                    return this.verifiedPublicKeyCache[cacheKey].publicKey;
                }
            }
        }
        let publicKey = await this.verifyCertificateChainWithoutCaching(trustedRoots, leaf, intermediate, effectiveDate);
        if (this.enableOnlineChecks) {
            this.verifiedPublicKeyCache[cacheKey] = new CacheValue(leaf.publicKey, new Date().getTime() + CACHE_TIME_LIMIT);
            if (Object.keys(this.verifiedPublicKeyCache).length > MAXIMUM_CACHE_SIZE) {
                for (let key in Object.keys(this.verifiedPublicKeyCache)) {
                    if (this.verifiedPublicKeyCache[key].cacheExpiry < new Date().getTime()) {
                        delete this.verifiedPublicKeyCache[key];
                    }
                }
            }
        }
        return publicKey;
    }
    async verifyCertificateChainWithoutCaching(trustedRoots, leaf, intermediate, effectiveDate) {
        let validity = false;
        let rootCert;
        for (const root of trustedRoots) {
            if (intermediate.verify(root.publicKey) && intermediate.issuer === root.subject) {
                validity = true;
                rootCert = root;
            }
        }
        validity = validity && leaf.verify(intermediate.publicKey) && leaf.issuer === intermediate.subject;
        validity = validity && intermediate.ca;
        const jsrsassignX509Leaf = new jsrsasign_1.X509();
        jsrsassignX509Leaf.readCertHex(leaf.raw.toString('hex'));
        const jsrassignX509Intermediate = new jsrsasign_1.X509();
        jsrassignX509Intermediate.readCertHex(intermediate.raw.toString('hex'));
        validity = validity && jsrsassignX509Leaf.getExtInfo("1.2.840.113635.100.6.11.1") !== undefined;
        validity = validity && jsrassignX509Intermediate.getExtInfo("1.2.840.113635.100.6.2.1") !== undefined;
        if (!validity) {
            throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
        }
        rootCert = rootCert;
        this.checkDates(leaf, effectiveDate);
        this.checkDates(intermediate, effectiveDate);
        this.checkDates(rootCert, effectiveDate);
        if (this.enableOnlineChecks) {
            await Promise.all([this.checkOCSPStatus(leaf, intermediate), this.checkOCSPStatus(intermediate, rootCert)]);
        }
        return leaf.publicKey;
    }
    async checkOCSPStatus(cert, issuer) {
        const authorityRex = /^OCSP - URI:(.*)$/m;
        const matchResult = cert.infoAccess ? authorityRex.exec(cert.infoAccess) : "";
        if (matchResult === null || matchResult.length !== 2) {
            throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE);
        }
        const request = new jsrsasign_1.KJUR.asn1.ocsp.OCSPRequest({ reqList: [{ issuerCert: issuer.toString(), subjectCert: cert.toString(), alg: "sha256" }] });
        const headers = new node_fetch_1.Headers();
        headers.append('Content-Type', 'application/ocsp-request');
        let response;
        try {
            response = await (0, node_fetch_1.default)(matchResult[1], {
                headers: headers,
                method: 'POST',
                body: Buffer.from(request.getEncodedHex(), 'hex'),
                timeout: 30000
            });
            if (!response.ok) {
                throw new VerificationException(VerificationStatus.RETRYABLE_VERIFICATION_FAILURE);
            }
        }
        catch (error) {
            if (error instanceof VerificationException) {
                throw error;
            }
            // Network errors
            throw new VerificationException(VerificationStatus.RETRYABLE_VERIFICATION_FAILURE, error instanceof Error ? error : undefined);
        }
        const responseBuffer = await response.buffer();
        const parsedResponse = new jsrsasign_1.KJUR.asn1.ocsp.OCSPParser().getOCSPResponse(responseBuffer.toString('hex'));
        // The issuer could also be the signer
        const jsrassignX509Issuer = new jsrsasign_1.X509();
        jsrassignX509Issuer.readCertHex(issuer.raw.toString('hex'));
        const allCerts = [jsrassignX509Issuer];
        for (const certHex of parsedResponse.certs) {
            const cert = new jsrsasign_1.X509();
            cert.readCertHex(certHex);
            allCerts.push(cert);
        }
        let signingCert = null;
        if (parsedResponse.respid.key) {
            for (const cert of allCerts) {
                const shasum = (0, crypto_1.createHash)('sha1');
                shasum.update(Buffer.from(cert.getSPKIValue(), 'hex'));
                const spkiHash = shasum.digest('hex');
                if (spkiHash === parsedResponse.respid.key) {
                    signingCert = new crypto_1.X509Certificate(Buffer.from(cert.hex, 'hex'));
                }
            }
        }
        else if (parsedResponse.respid.name) {
            for (const cert of allCerts) {
                if (cert.getSubject().str === parsedResponse.respid.name.str) {
                    signingCert = new crypto_1.X509Certificate(Buffer.from(cert.hex, 'hex'));
                }
            }
        }
        if (signingCert == null) {
            throw new VerificationException(VerificationStatus.FAILURE);
        }
        // Verify Signing Cert is issued by issuer
        if (signingCert.publicKey === issuer.publicKey && signingCert.subject === issuer.subject) {
            // This is directly signed by the issuer
        }
        else if (signingCert.verify(issuer.publicKey)) {
            // This is issued by the issuer, let's check the dates and purpose
            const signingCertAssign = new jsrsasign_1.X509();
            signingCertAssign.readCertPEM(signingCert.toString());
            if (!signingCertAssign.getExtExtKeyUsage().array.includes("ocspSigning")) {
                throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE);
            }
            this.checkDates(signingCert, new Date());
        }
        else {
            throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE);
        }
        // Extract raw responseData
        const responseData = jsrsasign_1.ASN1HEX.getTLVbyList(responseBuffer.toString('hex'), 0, [1, 0, 1, 0, 0]);
        // Verify Payload signed by cert
        const shortAlg = parsedResponse.alg.substring(0, 6).toUpperCase();
        if (shortAlg !== "SHA256" && shortAlg !== "SHA384" && shortAlg !== "SHA512") {
            throw new VerificationException(VerificationStatus.FAILURE);
        }
        if (!(0, crypto_1.verify)(shortAlg, Buffer.from(responseData, 'hex'), signingCert.publicKey, Buffer.from(parsedResponse.sighex, 'hex'))) {
            throw new VerificationException(VerificationStatus.FAILURE);
        }
        for (const singleResponse of parsedResponse.array) {
            // Confirm entry is for this cert
            const certIdBuilder = new jsrsasign_1.KJUR.asn1.ocsp.CertID();
            const currentCertCertId = certIdBuilder.getParamByCerts(issuer.toString(), cert.toString(), 'sha256');
            if (!(currentCertCertId.alg === singleResponse.certid.alg && currentCertCertId.issname === singleResponse.certid.issname &&
                currentCertCertId.isskey === singleResponse.certid.isskey && currentCertCertId.sbjsn === singleResponse.certid.sbjsn)) {
                continue;
            }
            // Validate contents
            const issueDate = this.parseX509Date(singleResponse.thisupdate);
            const nextDate = this.parseX509Date(singleResponse.nextupdate);
            if (singleResponse.status.status !== 'good' || new Date().getTime() + MAX_SKEW < issueDate.getTime() || nextDate.getTime() < new Date().getTime() - MAX_SKEW) {
                throw new VerificationException(VerificationStatus.FAILURE);
            }
            // Success
            return;
        }
        throw new VerificationException(VerificationStatus.FAILURE);
    }
    checkDates(cert, effectiveDate) {
        if (new Date(cert.validFrom).getTime() > (effectiveDate.getTime() + MAX_SKEW) ||
            new Date(cert.validTo).getTime() < (effectiveDate.getTime() - MAX_SKEW)) {
            throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE);
        }
    }
    parseX509Date(date) {
        return new Date(date.replace(/^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)$/, '$4:$5:$6 $2/$3/$1'));
    }
    extractSignedDate(decodedJWT) {
        return decodedJWT.signedDate === undefined ? new Date() : new Date(decodedJWT.signedDate);
    }
}
export var VerificationStatus;
(function (VerificationStatus) {
    VerificationStatus[VerificationStatus["OK"] = 0] = "OK";
    VerificationStatus[VerificationStatus["VERIFICATION_FAILURE"] = 1] = "VERIFICATION_FAILURE";
    VerificationStatus[VerificationStatus["RETRYABLE_VERIFICATION_FAILURE"] = 2] = "RETRYABLE_VERIFICATION_FAILURE";
    VerificationStatus[VerificationStatus["INVALID_APP_IDENTIFIER"] = 3] = "INVALID_APP_IDENTIFIER";
    VerificationStatus[VerificationStatus["INVALID_ENVIRONMENT"] = 4] = "INVALID_ENVIRONMENT";
    VerificationStatus[VerificationStatus["INVALID_CHAIN_LENGTH"] = 5] = "INVALID_CHAIN_LENGTH";
    VerificationStatus[VerificationStatus["INVALID_CERTIFICATE"] = 6] = "INVALID_CERTIFICATE";
    VerificationStatus[VerificationStatus["FAILURE"] = 7] = "FAILURE";
})(VerificationStatus || (VerificationStatus = {}));
export class VerificationException extends Error {
    constructor(status, cause) {
        super();
        this.status = status;
        this.cause = cause;
    }
}

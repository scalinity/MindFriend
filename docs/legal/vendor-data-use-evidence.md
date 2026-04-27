# Vendor Data-Use Evidence — for the §6.2 "no-training" claim in MindFriend's privacy policy

Last reviewed: 2026-04-26 by Daniel + Claude.

---

## xAI

**Source URL(s):**
- Enterprise Terms of Service (current): https://x.ai/legal/terms-of-service-enterprise
- Enterprise FAQs: https://x.ai/legal/faq-enterprise
- GSA-approved Enterprise Customer Agreement (April 2025): https://fedscoop.com/wp-content/uploads/sites/5/2025/08/xAI-Enterprise-Customer-Agreement-GSA-Approved-6.26.25.pdf

**Retrieved:** 2026-04-26

**Relevant clause(s) (verbatim or paraphrased):**

From the current xAI Enterprise Terms of Service, Section 3.3 (De-identified Data and Data Retention):
> "For clarity, subject to Section 3.2, xAI shall not use any User Content for any of its internal AI or other training purposes (such as training its machine learning models), including developing new products or services based on User Content. User Content is automatically deleted within 30 days, unless (a) xAI is legally required to retain it, or (b) it is flagged for safety, compliance, or moderation issues or as potentially violating this Agreement or the AUP."

From the xAI Enterprise FAQs:
> "Does xAI train its models using your business data? No, we do not use your business data, including inputs (prompts) or outputs (answers), for training our models. In some instances we may offer free credits in exchange for you agreeing to permit us to train on your business data."

**Important caveat:** These protections apply specifically to the xAI API under the Enterprise Terms. The consumer Grok product (grok.com) operates under separate Consumer Terms, which permit training on user content by default (opt-out available to logged-in users; unauthenticated users cannot opt out). MindFriend accesses xAI via the API under enterprise terms, so the enterprise clause governs.

**Conclusion:** ✅ Supports — the claim that API data submitted under xAI Enterprise Terms is not used to train xAI's general foundation models without explicit opt-in. The enterprise no-training commitment is explicit and contractual. The carve-out for "free credits in exchange for training consent" confirms the default is no training.

---

## OpenAI

**Source URL(s):**
- Data controls in the OpenAI platform (developer docs): https://developers.openai.com/api/docs/guides/your-data
- Enterprise privacy at OpenAI: https://openai.com/enterprise-privacy/

**Retrieved:** 2026-04-26

**Relevant clause(s) (verbatim or paraphrased):**

From the OpenAI developer documentation ("Data controls in the OpenAI platform"):
> "Your data is your data. As of March 1, 2023, data sent to the OpenAI API is not used to train or improve OpenAI models (unless you explicitly opt in to share data with us)."

The same page includes a per-endpoint table. Every listed endpoint — including `/v1/chat/completions`, `/v1/responses`, `/v1/audio/speech`, `/v1/embeddings`, and all others — shows "No" in the "Data used for training" column. Default abuse-monitoring retention is 30 days for most endpoints; Zero Data Retention is available for eligible endpoints.

From the OpenAI Enterprise Privacy page:
> "By default, data from ChatGPT Business, ChatGPT Enterprise, ChatGPT for Healthcare, ChatGPT Edu, ChatGPT for Teachers, and the API Platform (after March 1, 2023) isn't used for training our models, unless you have explicitly opted in to share your data with us to improve the services."

And from the Model Training FAQ on the same page:
> "By default, we do not use your business data for training our models. If you have explicitly opted in to share your data with us (for example, through our opt-in feedback mechanisms) to improve our services, then we may use the shared data to train our models."

**Conclusion:** ✅ Supports — the claim that API-submitted data is not used to train OpenAI's general foundation models without explicit opt-in. This commitment has been in effect since March 1, 2023, is stated explicitly in developer documentation, and is reflected in per-endpoint policy tables. The opt-in direction of consent is clear.

---

## Google Cloud Text-to-Speech

**Source URL(s):**
- Google Cloud Service Specific Terms (Section 18, Training Restriction): https://cloud.google.com/terms/service-terms
- Cloud Speech-to-Text Data Usage FAQ (the closest parallel Google publishes for its Cloud Speech AI services): https://docs.cloud.google.com/speech-to-text/docs/v1/data-usage-faq

**Retrieved:** 2026-04-26

**Relevant clause(s) (verbatim or paraphrased):**

From the Google Cloud Service Specific Terms, Section 18 (Training Restriction):
> "Google will not use Customer Data to train or fine-tune any AI/ML models without Customer's prior permission or instruction."

This clause sits in the general AI/ML services section of the Service Specific Terms and applies to Google Cloud AI/ML services, which includes Cloud Text-to-Speech. It is a blanket contractual commitment across Google Cloud's AI offerings.

Additionally, from the Cloud Speech-to-Text Data Usage FAQ (the closest published data-usage FAQ for Google Cloud speech AI services; Google does not publish a separate TTS-specific FAQ, but the policy language is the same family of services):
> "If you are not enrolled in the data logging opt-in program, Google does not use any of your content for any purpose except to provide you with the Cloud Speech-to-Text API service."
> "Google only uses data from customers who have opted in to data logging and agreed to the relevant terms to improve its services. Data from customers who have not opted in to data logging is not stored or used by Google for anything other than providing the service to the customer."

**Important note on TTS-specific documentation:** Google does not publish a standalone "Cloud Text-to-Speech Data Usage FAQ" page equivalent to the Speech-to-Text FAQ. The primary contractual protection for TTS customers is the Service Specific Terms Section 18 Training Restriction quoted above, which is binding for all Google Cloud AI/ML service customers. The Speech-to-Text FAQ is cited as corroborating evidence of Google's consistent policy posture for Cloud Speech AI services, but it is not a TTS-specific document.

**Conclusion:** ✅ Supports — the claim that text submitted to Google Cloud Text-to-Speech is not used to train Google's general foundation models without explicit opt-in. The Service Specific Terms Section 18 Training Restriction is a clear contractual prohibition. The opt-in data-logging program is the only pathway for Google to use customer content to improve services.

---

## Decision

All three vendors return ✅ on the "no training without explicit opt-in" standard when accessed via their respective API / enterprise tiers.

**Recommendation: KEEP STRONG CLAIM**

The sentence in MindFriend's privacy policy asserting that AI vendors accessed via the API do not use submitted data to train their general foundation models without explicit opt-in is supported by current, publicly accessible contractual terms from all three vendors as of 2026-04-26.

**Suggested annual review trigger:** Re-verify all three URLs each year, or immediately upon any vendor terms-of-service update notification. Pay particular attention to xAI, whose consumer and enterprise terms differ substantially; any change to the enterprise no-training clause would require immediate re-evaluation and likely weakening of the privacy policy claim.

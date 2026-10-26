# MindFriend Project Instructions

## App Store delivery

- Treat a request to upload or deliver a MindFriend production App Store update as authorization to complete the full workflow: upload the latest verified build, wait for processing, attach the exact build to the correct App Store version, complete the required review details, and submit it to Apple App Review. Uploading to App Store Connect alone is not completion; do not require a separate request to submit for review.
- Select **Automatically release this version** so Apple publishes the update after approval. Use upload-only, TestFlight-only, manual release, or a scheduled release only when explicitly requested for that delivery.
- Before reporting delivery complete, verify the exact version and build are **Waiting for Review**, **In Review**, or already approved, and confirm that automatic release is saved. If Apple blocks the workflow, report the exact blocker and remaining step without claiming submission succeeded.
- Preserve existing users, data, privacy, review sign-in details, and unrelated App Store configuration throughout the delivery.

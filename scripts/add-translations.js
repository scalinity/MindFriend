#!/usr/bin/env node

/**
 * Add Spanish (es) and Portuguese (pt-BR) translation templates to Localizable.xcstrings
 * Marks all strings as "needs_translation" for professional translation
 */

const fs = require("fs");
const path = require("path");

const LOCALIZABLE_PATH = path.join(
  __dirname,
  "../apps/ios/MindFriendApp/Resources/Localizable.xcstrings",
);

console.log("Reading Localizable.xcstrings...");
const localizableContent = fs.readFileSync(LOCALIZABLE_PATH, "utf8");
const localizable = JSON.parse(localizableContent);

let stringsProcessed = 0;
let stringsWithLocalizations = 0;

console.log("Adding ES and PT-BR translation templates...");

// Iterate through all string keys
for (const [key, value] of Object.entries(localizable.strings || {})) {
  stringsProcessed++;

  // Skip if localizations already exist
  if (
    value.localizations &&
    (value.localizations.es || value.localizations["pt-BR"])
  ) {
    stringsWithLocalizations++;
    continue;
  }

  // Initialize localizations if it doesn't exist
  if (!value.localizations) {
    value.localizations = {};
  }

  // Add Spanish translation template
  if (!value.localizations.es) {
    value.localizations.es = {
      stringUnit: {
        state: "needs_translation",
        value: "",
      },
    };
  }

  // Add Portuguese (Brazil) translation template
  if (!value.localizations["pt-BR"]) {
    value.localizations["pt-BR"] = {
      stringUnit: {
        state: "needs_translation",
        value: "",
      },
    };
  }
}

console.log(`Processed ${stringsProcessed} strings`);
console.log(`${stringsWithLocalizations} already had localizations`);
console.log(
  `${stringsProcessed - stringsWithLocalizations} updated with new templates`,
);

// Write back to file with proper formatting
console.log("Writing updated Localizable.xcstrings...");
fs.writeFileSync(
  LOCALIZABLE_PATH,
  JSON.stringify(localizable, null, 2) + "\n",
  "utf8",
);

console.log("✅ Translation templates added successfully!");
console.log("Next steps:");
console.log("  1. Open Xcode and verify the strings appear correctly");
console.log(
  "  2. Export strings for translation (Product > Export Localizations)",
);
console.log("  3. Send .xliff files to professional translators");
console.log("  4. Import translated .xliff files back into Xcode");

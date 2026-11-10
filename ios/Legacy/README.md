# Legacy

Code replaced by the template-based rebuild, kept as a way back. Nothing in
this folder is compiled: it sits outside the `DosarCuSina` synchronized group,
so Xcode ignores it.

It holds the first version of the app: the 90-field `Asset` model and its
siblings, the hand-built screens, and services written against that model
(notification scheduler, widget sync, PDF dossier, finance calculator,
calendar export, demo seeder, category display settings, the v2 archive
service), and `Services/LocalOCRService.swift`, replaced by the capture
pipeline in `Services/Capture`. `Services/OCR/RomanianUtilityParser.swift` is the
first bill reader, with the capture adapter it had (`LegacyUtilityInvoiceParser`),
replaced by the bill kind's label table (`BillReader`, `ContractReader`,
`UtilityProviders`); docs/HANDOFF.md says how to switch back. `Services/Capture/LegacyNumberReaders.swift` holds the policy and invoice number readings from before values printed in parts had one rule (`CompositeValue`), with the label list the first used; its header says how to switch one back. `Widgets/` holds the first widget code, which
was never a target; the real widget extension is `ios/DosarCuSinaWidgets`.

Wave-2 screens and services port what is still useful from here onto the new
model. Delete this folder only after the new app has been used for a while and
the owner agrees.

`Config.xcconfig.template` is the old developer key file. The project never read it; the Gemini key is entered in Settings.

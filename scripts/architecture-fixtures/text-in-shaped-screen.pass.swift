// path: ios/DosarCuSina/Views/Add/AddVisitFlow.swift
// The kind says "Salvează vizita"; the screen only draws it.
        .dsPinnedAction {
            DSPrimaryButton(verbatim: shape.save, systemImage: "checkmark") { save() } // never "Salvează" here
        }
        Image(systemName: "checkmark.circle.fill")
        Text(verbatim: "\(entry.title) · \(DosarFormat.longDay(entry.occurredAt))")
        DSTextField(LocalizedStringKey(shape.work?.rowName ?? ""), text: $extra.name)

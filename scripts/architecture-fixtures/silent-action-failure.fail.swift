// path: ios/DosarCuSina/Views/Example/ExampleScreen.swift
toast = DSToast.undo(message) { try? ObligationActions(context: context).undo(entry) }
_ = try? TemplateStore(context: context).installBuiltIns()
try? store.setOnHome(category, true)
try? repairs.refresh(in: context, announce: true)
try? DataRepairCenter.shared.refresh(in: container.mainContext, announce: true)
_ = try? HouseholdRules.reconcile(in: context, today: today)
_ = try? LaunchData.reconcileHouseholdRules(in: context, today: today)

// path: ios/DosarCuSina/Services/Reminders/NotificationReconciler.swift
let parts = Calendar.dosar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
let soon = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)

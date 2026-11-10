// path: ios/DosarCuSina/Services/Documents/ExampleDrawer.swift
guard let context = ImageScaling.canvas(width: width, height: height, onWhite: true) else { return nil }
let smaller = ImageScaling.scaled(image, toLongEdge: 2400, .down)
// A PDF being written is another job.
let pdf = CGContext(consumer: consumer, mediaBox: nil, nil)

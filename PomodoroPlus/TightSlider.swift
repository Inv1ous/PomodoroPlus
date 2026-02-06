//
//  TightSlider.swift
//  PomodoroPlus
//
//  Created by Sora K on 4/2/2026.
//


import SwiftUI
import AppKit

struct TightSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = TightNSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        slider.isContinuous = true
        slider.controlSize = .small
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        if nsView.doubleValue != value { nsView.doubleValue = value }
        if nsView.minValue != range.lowerBound { nsView.minValue = range.lowerBound }
        if nsView.maxValue != range.upperBound { nsView.maxValue = range.upperBound }
    }

    final class Coordinator: NSObject {
        var parent: TightSlider
        init(_ parent: TightSlider) { self.parent = parent }

        @objc func changed(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }
    }
}

final class TightNSSlider: NSSlider {
    override var alignmentRectInsets: NSEdgeInsets {
        .init(top: 0, left: 0, bottom: 0, right: 0) // 👈 removes the “mystery gap”
    }
}

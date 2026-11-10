import Puzzle
import SwiftUI

/// Nine markers, ring 1 on the left as in the side view, filled for a ring that is on. Tapping one moves that
/// ring if the rule allows; otherwise the ring in the way is marked and a line says why.
struct RingStrip: View {
    let model: ToyModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(PuzzleState.rings, id: \.self) { ring in
                    RingMarker(
                        ring: ring,
                        isOn: model.state.isOn(ring),
                        role: role(of: ring)
                    ) {
                        withAnimation(.snappy(duration: 0.2)) { model.tap(ring) }
                    }
                }
            }
            HStack(spacing: 12) {
                Text(model.moveCount == 1 ? "1 move" : "\(model.moveCount) moves")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(message)
                    .foregroundStyle(model.refusal == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func role(of ring: Int) -> RingMarker.Role {
        guard let refusal = model.refusal else { return .plain }
        if ring == refusal.ring { return .refused }
        if ring == refusal.blockingRing { return .blocking }
        return .plain
    }

    private var message: String {
        guard let refusal = model.refusal else {
            return model.state == .allOff ? "All rings are off" : "Tap a ring to move it"
        }
        switch refusal.block {
        case .earlierRingOn(let earlier):
            return "Ring \(earlier) is on, so ring \(refusal.ring) can’t move"
        case .previousRingOff(let previous):
            return "Ring \(previous) is off, so ring \(refusal.ring) can’t move"
        }
    }
}

/// One ring's marker: a filled disc when the ring is on, an outline when it is off.
private struct RingMarker: View {
    enum Role { case plain, refused, blocking }

    let ring: Int
    let isOn: Bool
    let role: Role
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                    Circle()
                        .strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary), lineWidth: 1.5)
                    if role != .plain {
                        Circle()
                            .strokeBorder(highlight, lineWidth: 3)
                            .padding(-5)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(5)
                Text("\(ring)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ring \(ring)")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(role == .blocking ? "Blocks the ring you tapped" : "Moves this ring")
    }

    private var highlight: Color {
        role == .refused ? .red : .orange
    }
}

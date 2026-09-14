import XCTest
@testable import Claudio

/// The microphone's loudness, as the panel draws it: a number between 0 and
/// 1 that moves with the voice and stays at rest in a quiet room.
final class AudioLevelTests: XCTestCase {

    func testSilenceIsZero() {
        XCTAssertEqual(level([Float](repeating: 0, count: 480)), 0)
    }

    func testNoSamplesIsZero() {
        XCTAssertEqual(level([]), 0)
    }

    func testFullScaleIsOne() {
        XCTAssertEqual(level([Float](repeating: 1, count: 480)), 1)
    }

    /// Room noise sits under the floor and draws nothing; a voice close to a
    /// laptop's microphone reaches the ceiling.
    func testTheScaleRunsFromTheFloorToTheCeilingInDecibels() {
        XCTAssertEqual(AudioLevel.normalized(decibels: AudioLevel.floor), 0)
        XCTAssertEqual(AudioLevel.normalized(decibels: AudioLevel.ceiling), 1)
        let middle = (AudioLevel.floor + AudioLevel.ceiling) / 2
        XCTAssertEqual(AudioLevel.normalized(decibels: middle), 0.5, accuracy: 0.001)
        XCTAssertEqual(AudioLevel.normalized(decibels: -120), 0)
        XCTAssertEqual(AudioLevel.normalized(decibels: 6), 1)
    }

    /// A sine at -30 dBFS peak has an RMS 3 dB lower: the measure is the
    /// RMS, which is what loudness follows, not the peak.
    func testTheMeasureIsTheRootMeanSquare() {
        let amplitude = Float(pow(10.0, -30.0 / 20.0))
        let sine = (0..<4800).map { amplitude * Float(sin(2 * Double.pi * 440 * Double($0) / 48000)) }
        let expected = AudioLevel.normalized(decibels: -33.01)
        XCTAssertEqual(level(sine), expected, accuracy: 0.01)
    }

    private func level(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { AudioLevel.level(of: $0) }
    }
}

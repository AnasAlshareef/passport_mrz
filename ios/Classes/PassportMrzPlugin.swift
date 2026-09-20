import Flutter
import UIKit
import Vision

/// Native OCR for the `passport_mrz/text_recognition` channel, backed by Vision.
///
/// Avoids google_mlkit_text_recognition on iOS: ML Kit's pods ship fat
/// frameworks whose only simulator slice is x86_64, so they cannot link on an
/// Apple Silicon iOS 26+ simulator. Vision is part of the OS and needs no pod.
public class PassportMrzPlugin: NSObject, FlutterPlugin {
  static let channelName = "passport_mrz/text_recognition"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "BAD_ARGS", message: "path is required", details: nil))
        return
      }
      let rotation = args["rotation"] as? Int ?? 0
      recognize(path: path, rotation: rotation, result: result)
    }
  }

  private static func recognize(
    path: String,
    rotation: Int,
    result: @escaping FlutterResult
  ) {
    guard
      let loaded = UIImage(contentsOfFile: path),
      let cgImage = uprightCGImage(from: rotated(loaded, degrees: rotation))
    else {
      result(FlutterError(code: "BAD_IMAGE", message: "cannot read image at \(path)", details: nil))
      return
    }

    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)

    // Vision invokes this on whatever queue `perform` was called from, but a
    // FlutterResult must be delivered on the main thread.
    let reply: (Any?) -> Void = { value in
      DispatchQueue.main.async { result(value) }
    }

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        reply(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
        return
      }

      let observations = request.results as? [VNRecognizedTextObservation] ?? []
      var lines: [[String: Any]] = []
      var texts: [String] = []

      for observation in observations {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let text = candidate.string
        texts.append(text)

        // Vision boxes are normalised with a bottom-left origin; ML Kit (and
        // therefore the MRZ heuristics) expect pixels with a top-left origin.
        let box = observation.boundingBox
        let left = box.minX * width
        let top = (1.0 - box.maxY) * height
        let right = box.maxX * width
        let bottom = (1.0 - box.minY) * height

        lines.append([
          "text": text,
          "rect": [left, top, right, bottom],
          "words": text.split(whereSeparator: { $0.isWhitespace }).map(String.init),
        ])
      }

      // Vision has no block concept — one block holding every line keeps the
      // `blocks -> lines` traversal on the Dart side valid.
      reply([
        "text": texts.joined(separator: "\n"),
        "blocks": [["lines": lines]],
      ])
    }

    request.recognitionLevel = .accurate
    // MRZ is not natural language: correction rewrites '<<<' filler and
    // confuses OCR-B glyphs, so it must stay off.
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        reply(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  /// Rotates clockwise by 0/90/180/270 in memory.
  ///
  /// Replaces the old Dart-side rotation, which decoded, rotated, re-encoded a
  /// JPEG and wrote it to disk for every orientation attempt.
  private static func rotated(_ image: UIImage, degrees: Int) -> UIImage {
    let normalized = ((degrees % 360) + 360) % 360
    guard normalized != 0 else { return image }

    let radians = CGFloat(normalized) * .pi / 180
    let size = image.size
    // A quarter turn swaps the canvas dimensions.
    let canvas = normalized % 180 == 0
      ? size
      : CGSize(width: size.height, height: size.width)

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
      ctx.cgContext.translateBy(x: canvas.width / 2, y: canvas.height / 2)
      // UIKit's y axis points down, so a positive angle turns clockwise —
      // matching the `image` package's copyRotate that this replaces.
      ctx.cgContext.rotate(by: radians)
      image.draw(
        in: CGRect(
          x: -size.width / 2,
          y: -size.height / 2,
          width: size.width,
          height: size.height
        )
      )
    }
  }

  /// Redraws the image upright so EXIF orientation is baked into the bitmap.
  ///
  /// Vision reports boxes in the oriented space; normalising up front means the
  /// pixel conversion above can use the CGImage's own width/height.
  private static func uprightCGImage(from image: UIImage) -> CGImage? {
    if image.imageOrientation == .up { return image.cgImage }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    let redrawn = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    return redrawn.cgImage
  }
}

package ly.websters.passportmrz

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native OCR for the `passport_mrz/text_recognition` channel, backed by ML Kit.
 *
 * See PassportMrzPlugin.swift for the iOS half, which uses Vision.
 */
class PassportMrzPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val recognizer: TextRecognizer =
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        recognizer.close()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognize" -> recognize(
                call.argument<String>("path"),
                call.argument<Int>("rotation") ?: 0,
                result,
            )
            else -> result.notImplemented()
        }
    }

    private fun recognize(path: String?, rotation: Int, result: MethodChannel.Result) {
        if (path.isNullOrEmpty() || !File(path).exists()) {
            result.error("BAD_IMAGE", "cannot read image at $path", null)
            return
        }

        val image = try {
            if (rotation == 0) {
                // fromFilePath honours the file's EXIF orientation.
                InputImage.fromFilePath(context, Uri.fromFile(File(path)))
            } else {
                // ML Kit rotates internally and reports boxes in the rotated
                // space, so no re-encoded JPEG is needed per orientation.
                val bitmap = BitmapFactory.decodeFile(path)
                    ?: throw IllegalArgumentException("cannot decode $path")
                InputImage.fromBitmap(bitmap, rotation)
            }
        } catch (e: Exception) {
            result.error("BAD_IMAGE", e.message, null)
            return
        }

        recognizer.process(image)
            .addOnSuccessListener { visionText ->
                result.success(
                    mapOf(
                        "text" to visionText.text,
                        "blocks" to visionText.textBlocks.map { block ->
                            mapOf(
                                "lines" to block.lines.map { line ->
                                    mapOf(
                                        "text" to line.text,
                                        "rect" to rectToList(line.boundingBox),
                                        "words" to line.elements.map { it.text },
                                    )
                                },
                            )
                        },
                    ),
                )
            }
            .addOnFailureListener { e ->
                result.error("OCR_FAILED", e.message, null)
            }
    }

    /** ML Kit already reports pixels with a top-left origin — no conversion needed. */
    private fun rectToList(box: Rect?): List<Double> =
        if (box == null) {
            listOf(0.0, 0.0, 0.0, 0.0)
        } else {
            listOf(
                box.left.toDouble(),
                box.top.toDouble(),
                box.right.toDouble(),
                box.bottom.toDouble(),
            )
        }

    companion object {
        const val CHANNEL = "passport_mrz/text_recognition"
    }
}

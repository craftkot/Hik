package com.ehtid.game_lab

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.ArrayDeque

/**
 * Android Storage Access Framework bridge. No MANAGE_EXTERNAL_STORAGE and no
 * attempt to bypass Android/data/obb restrictions.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "ehtid.gamelab/storage"
    private val overlayChannelName = "ehtid.gamelab/overlay"
    private val pickFolderCode = 8812
    private val maxFileSize = 8L * 1024 * 1024
    private var pendingPicker: MethodChannel.Result? = null
    private var grantedTree: Uri? = null
    // The document IDs returned by SAF can be opaque, not path-like. Keep the
    // parent relationship provided by the actual directory listing.
    private val documentParents = HashMap<String, String>()
    private val documentNames = HashMap<String, String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, overlayChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(mapOf(
                            "permission" to Settings.canDrawOverlays(this),
                            "supported" to (Build.VERSION.SDK_INT >= 26)
                        ))
                        "start" -> {
                            if (!Settings.canDrawOverlays(this)) {
                                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")))
                                result.success("permission_required")
                            } else {
                                val service = Intent(this, OverlayService::class.java)
                                if (Build.VERSION.SDK_INT >= 26) startForegroundService(service)
                                else startService(service)
                                result.success("started")
                            }
                        }
                        "stop" -> {
                            stopService(Intent(this, OverlayService::class.java))
                            result.success("stopped")
                        }
                        "takeNumber" -> {
                            val prefs = getSharedPreferences(OverlayService.PREFS, MODE_PRIVATE)
                            val number = prefs.getString(OverlayService.KEY_NUMBER, null)
                            prefs.edit().remove(OverlayService.KEY_NUMBER).apply()
                            result.success(number)
                        }
                        else -> result.notImplemented()
                    }
                } catch (exception: Exception) {
                    result.error("overlay", exception.message ?: "Overlay unavailable", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, reply ->
                try {
                    when (call.method) {
                        "chooseFolder" -> {
                            if (pendingPicker != null) {
                                reply.error("busy", "Folder picker is already open", null)
                            } else {
                                pendingPicker = reply
                                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                startActivityForResult(intent, pickFolderCode)
                            }
                        }
                        "scanFolder" -> {
                            val uri = Uri.parse(call.argument<String>("uri") ?: error("Missing URI"))
                            checkAccess(uri)
                            reply.success(scanTree(uri))
                        }
                        "readPrefix" -> {
                            val uri = Uri.parse(call.argument<String>("uri") ?: error("Missing URI"))
                            checkDocumentAccess(uri)
                            reply.success(readPrefix(uri))
                        }
                        "readDocument" -> {
                            val uri = Uri.parse(call.argument<String>("uri") ?: error("Missing URI"))
                            checkDocumentAccess(uri)
                            reply.success(readBytes(uri))
                        }
                        "writeWithBackup" -> {
                            val uri = Uri.parse(call.argument<String>("uri") ?: error("Missing URI"))
                            checkDocumentAccess(uri)
                            val name = call.argument<String>("name") ?: error("Missing name")
                            val data = call.argument<ByteArray>("data") ?: error("Missing data")
                            if (data.size > maxFileSize) error("File exceeds safe write limit")
                            reply.success(writeWithBackup(uri, name, data))
                        }
                        else -> reply.notImplemented()
                    }
                } catch (exception: Exception) {
                    reply.error("storage", exception.message ?: "Unknown storage error", null)
                }
            }
    }

    @Deprecated("Uses Storage Access Framework picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFolderCode) return
        val result = pendingPicker
        pendingPicker = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }
        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            grantedTree = uri
            documentParents.clear()
            documentNames.clear()
            result?.success(uri.toString())
        } catch (exception: Exception) {
            result?.error("permission", exception.message, null)
        }
    }

    private fun checkAccess(tree: Uri) {
        val permitted = contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission
        }
        if (!permitted) error("Select this folder with the system picker")
        grantedTree = tree
    }

    private fun checkDocumentAccess(uri: Uri) {
        val tree = grantedTree ?: error("Choose a game folder first")
        if (uri.authority != tree.authority) error("Document belongs to a different provider")
        if (uri.scheme != "content") error("Only content:// document URIs are permitted")
        val documentId = DocumentsContract.getDocumentId(uri)
        if (!documentParents.containsKey(documentId)) {
            error("Document not found in the selected folder scan")
        }
        checkAccess(tree)
    }

    private fun scanTree(tree: Uri): List<Map<String, Any>> {
        documentParents.clear()
        documentNames.clear()
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        data class Pending(val id: String, val path: String, val depth: Int)
        val queue = ArrayDeque<Pending>()
        queue.add(Pending(rootId, "", 0))
        val result = ArrayList<Map<String, Any>>()
        var visited = 0
        while (queue.isNotEmpty() && visited < 3500 && result.size < 2500) {
            val (parentId, prefix, depth) = queue.removeFirst()
            if (depth >= 12) continue
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
            contentResolver.query(children, arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE
            ), null, null, null)?.use { cursor ->
                while (cursor.moveToNext() && result.size < 2500) {
                    visited++
                    val id = cursor.getString(0) ?: continue
                    val name = cursor.getString(1) ?: continue
                    val mime = cursor.getString(2) ?: ""
                    val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                    val path = if (prefix.isEmpty()) name else "$prefix/$name"
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (visited < 3500) queue.add(Pending(id, path, depth + 1))
                    } else if (!name.contains(".ehtid-backup-")) {
                        documentParents[id] = parentId
                        documentNames[id] = name
                        val document = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                        result.add(mapOf(
                            "uri" to document.toString(),
                            "name" to name,
                            "relativePath" to path,
                            "size" to size
                        ))
                    }
                }
            }
        }
        return result
    }

    private fun readPrefix(uri: Uri): ByteArray {
        val buffer = ByteArray(4096)
        val count = contentResolver.openInputStream(uri)?.use { it.read(buffer) }
            ?: error("Unable to open document")
        if (count <= 0) return ByteArray(0)
        return buffer.copyOf(count)
    }

    private fun readBytes(uri: Uri): ByteArray {
        val data = ByteArrayOutputStream()
        contentResolver.openInputStream(uri)?.use { input ->
            val chunk = ByteArray(32768)
            var total = 0L
            while (true) {
                val read = input.read(chunk)
                if (read < 0) break
                total += read
                if (total > maxFileSize) error("File exceeds 8 MB preview limit")
                data.write(chunk, 0, read)
            }
        } ?: error("Unable to open document")
        return data.toByteArray()
    }

    private fun writeWithBackup(uri: Uri, name: String, content: ByteArray): String {
        val tree = grantedTree ?: error("No folder grant")
        val docId = DocumentsContract.getDocumentId(uri)
        val parentId = documentParents[docId]
            ?: error("File is not part of the scanned folder")
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, parentId)
        val actualName = documentNames[docId] ?: error("Unknown file name")
        if (actualName != name) error("File name changed after scan")
        val backupName = "$actualName.ehtid-backup-${System.currentTimeMillis()}.bak"
        val backupUri = DocumentsContract.createDocument(contentResolver, parent,
            "application/octet-stream", backupName)
            ?: error("Unable to create backup: original not changed")

        // Make and verify an exact backup BEFORE any write to the original.
        try {
            contentResolver.openOutputStream(backupUri, "wt")?.use { output ->
                contentResolver.openInputStream(uri)?.use { input -> input.copyTo(output) }
                    ?: error("Unable to read original")
            } ?: error("Unable to write backup")
            if (!readBytes(uri).contentEquals(readBytes(backupUri))) {
                error("Backup verification failed, original not changed")
            }
            try {
                contentResolver.openOutputStream(uri, "wt")?.use { output ->
                    output.write(content)
                    output.flush()
                } ?: error("Original is not writable")
                if (!readBytes(uri).contentEquals(content)) {
                    error("Write verification failed")
                }
            } catch (writeError: Exception) {
                // A failed stream write may truncate the original. Attempt
                // immediate recovery from the verified backup, and keep the
                // backup regardless of whether recovery succeeds.
                val recovery = try {
                    contentResolver.openOutputStream(uri, "wt")?.use { output ->
                        contentResolver.openInputStream(backupUri)?.use { input ->
                            input.copyTo(output)
                        } ?: error("Cannot read backup")
                    } ?: error("Cannot restore original")
                    if (!readBytes(uri).contentEquals(readBytes(backupUri))) {
                        error("Restore verification failed")
                    }
                    "Original restored from backup"
                } catch (restoreError: Exception) {
                    "Automatic restore failed: ${restoreError.message}"
                }
                error("${writeError.message}; $recovery; copy: $backupName")
            }
            return backupName
        } catch (exception: Exception) {
            throw IllegalStateException("${exception.message}; backup: $backupName", exception)
        }
    }
}

package com.ehtid.game_lab

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
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

    // A document ID alone is NOT a unique locator across different SAF trees.
    // Cache the exact document URI and its originating tree/parent/name together.
    // Otherwise scanning folder B invalidates reads and backups from folder A.
    private data class DocumentEntry(val tree: Uri, val parentId: String,
                                     val name: String)
    private val documentEntries = HashMap<String, DocumentEntry>()

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
                        "listInstalledApps" -> {
                            // Visible launcher activities only. Android 11+ package
                            // visibility is declared in the generated manifest.
                            val launch = Intent(Intent.ACTION_MAIN)
                                .addCategory(Intent.CATEGORY_LAUNCHER)
                            @Suppress("DEPRECATION")
                            val apps = if (Build.VERSION.SDK_INT >= 33) {
                                packageManager.queryIntentActivities(
                                    launch, PackageManager.ResolveInfoFlags.of(0L))
                            } else {
                                packageManager.queryIntentActivities(launch, 0)
                            }
                            val entries = apps.mapNotNull { resolved ->
                                val pkg = resolved.activityInfo?.packageName
                                    ?: return@mapNotNull null
                                if (pkg == packageName) return@mapNotNull null
                                val label = resolved.loadLabel(packageManager)
                                    ?.toString()?.take(120)?.trim().orEmpty()
                                if (label.isEmpty()) return@mapNotNull null
                                @Suppress("DEPRECATION")
                                val isGame = try {
                                    Build.VERSION.SDK_INT >= 26 &&
                                        packageManager.getApplicationInfo(pkg, 0)
                                            .category == ApplicationInfo.CATEGORY_GAME
                                } catch (_: PackageManager.NameNotFoundException) {
                                    false
                                }
                                mapOf("package" to pkg, "label" to label,
                                    "isGame" to isGame)
                            }.distinctBy { it["package"] }
                                .sortedWith(compareByDescending<Map<String, Any>> {
                                    it["isGame"] == true
                                }.thenBy { (it["label"] as String).lowercase() })
                            reply.success(entries)
                        }
                        "grantedFolders" -> {
                            reply.success(contentResolver.persistedUriPermissions
                                .filter { it.isReadPermission &&
                                    it.uri.scheme == "content" }
                                .map { it.uri.toString() })
                        }
                        "linkGameFolder" -> {
                            val pkg = call.argument<String>("package")
                                ?: error("Missing package")
                            val uri = Uri.parse(call.argument<String>("uri")
                                ?: error("Missing tree URI"))
                            if (!Regex("^[a-zA-Z][a-zA-Z0-9_]*(\\\\.[a-zA-Z0-9_]+)+\\$").matches(pkg)) {
                                error("Invalid package")
                            }
                            // Only a root explicitly granted by the user may
                            // be associated with the selected app.
                            checkAccess(uri)
                            val prefs = getSharedPreferences("ehtid.game_roots", MODE_PRIVATE)
                            val key = "roots:$pkg"
                            val roots = prefs.getStringSet(key, emptySet())
                                ?.toMutableSet() ?: mutableSetOf()
                            if (roots.size >= 6 && !roots.contains(uri.toString())) {
                                error("Up to 6 user-approved folders per game")
                            }
                            roots.add(uri.toString())
                            prefs.edit().putStringSet(key, roots).apply()
                            reply.success(true)
                        }
                        "linkedGameFolders" -> {
                            val pkg = call.argument<String>("package")
                                ?: error("Missing package")
                            val allowed = contentResolver.persistedUriPermissions
                                .filter { it.isReadPermission }
                                .map { it.uri.toString() }.toSet()
                            val roots = getSharedPreferences("ehtid.game_roots", MODE_PRIVATE)
                                .getStringSet("roots:$pkg", emptySet()).orEmpty()
                                .filter { it in allowed }
                            reply.success(roots)
                        }
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
                            val expected = call.argument<ByteArray>("expected")
                            reply.success(writeWithBackup(uri, name, data, expected))
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
            // Preserve other previously selected tree grants and their files.
            result?.success(uri.toString())
        } catch (exception: Exception) {
            result?.error("permission", exception.message, null)
        }
    }

    private fun checkAccess(tree: Uri) {
        if (tree.scheme != "content") error("Only content:// tree URIs are permitted")
        val permitted = contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission
        }
        if (!permitted) error("Select this folder with the system picker")
    }

    private fun checkDocumentAccess(uri: Uri): DocumentEntry {
        if (uri.scheme != "content") error("Only content:// document URIs are permitted")
        val entry = documentEntries[uri.toString()]
            ?: error("Document not found in any user-approved folder scan")
        if (uri.authority != entry.tree.authority)
            error("Document belongs to a different provider")
        // Reconstruct URI from the granted root and document ID, rather than
        // trusting a raw URI merely because its provider authority matches.
        val expected = DocumentsContract.buildDocumentUriUsingTree(
            entry.tree, DocumentsContract.getDocumentId(uri))
        if (expected != uri) error("Document URI does not match its tree grant")
        checkAccess(entry.tree)
        return entry
    }

    private fun scanTree(tree: Uri): List<Map<String, Any>> {
        // Stage a fresh scan. Only replace this tree's cached entries after the
        // listing succeeded; do not discard entries from other granted roots.
        val discovered = HashMap<String, DocumentEntry>()
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
                        val document = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                        discovered[document.toString()] = DocumentEntry(tree, parentId, name)
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
        val oldKeys = documentEntries.filterValues { entry -> entry.tree == tree }.keys
        for (key in oldKeys) documentEntries.remove(key)
        documentEntries.putAll(discovered)
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

    private fun writeWithBackup(
        uri: Uri, name: String, content: ByteArray, expected: ByteArray?
    ): String {
        val entry = checkDocumentAccess(uri)
        if (expected != null && !readBytes(uri).contentEquals(expected)) {
            error("Game save changed after opening; reload it before editing")
        }
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            entry.tree, entry.parentId)
        val actualName = entry.name
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
            if (expected != null && !readBytes(uri).contentEquals(expected)) {
                error("Game changed the save during backup; write cancelled")
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

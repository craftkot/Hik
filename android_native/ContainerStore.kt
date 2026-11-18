package com.ehtid.game_lab

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import android.content.pm.PackageManager
import java.io.File
import java.io.FileOutputStream
import java.util.Properties
import java.util.UUID
import java.util.zip.ZipInputStream

/** An Android-only proof of concept. Web games run inside EHTID;
 * staged APKs require normal Android installation and run outside EHTID.
 */
class ContainerStore(private val context: Context) {
    private val base = File(context.filesDir, "ehtid_container_lab")
    private val validId = Regex("^[0-9a-f]{8}-[0-9a-f-]{27,36}$")
    private val maxInput = 200L * 1024 * 1024
    private val maxExtracted = 50L * 1024 * 1024

    private fun folder(id: String): File {
        require(validId.matches(id)) { "Invalid game ID" }
        return File(base, id)
    }

    private fun meta(id: String): Properties {
        val file = File(folder(id), "meta.properties")
        require(file.isFile) { "Game not found" }
        return Properties().apply { file.inputStream().use { load(it) } }
    }

    private fun saveMeta(dir: File, kind: String, name: String, pkg: String = "") {
        val info = Properties().apply {
            setProperty("kind", kind)
            setProperty("name", name.take(100))
            setProperty("package", pkg)
        }
        File(dir, "meta.properties").outputStream().use {
            info.store(it, "EHTID Game Lab")
        }
    }

    fun list(): List<Map<String, String>> =
        base.listFiles()?.filter { it.isDirectory }?.mapNotNull { dir ->
            try {
                val info = meta(dir.name)
                val kind = info.getProperty("kind", "")
                if (kind != "web" && kind != "apk") return@mapNotNull null
                mapOf("id" to dir.name, "kind" to kind,
                    "name" to info.getProperty("name", "Unnamed"),
                    "package" to info.getProperty("package", ""))
            } catch (_: Exception) { null }
        }?.sortedBy { it["name"]?.lowercase() } ?: emptyList()

    fun createDemo(): Map<String, String> {
        val id = UUID.randomUUID().toString()
        val dir = folder(id)
        require(dir.mkdirs())
        try {
            val web = File(dir, "web")
            require(web.mkdir())
            File(web, "index.html").writeText(
                """<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8">
                <meta name="viewport" content="width=device-width,initial-scale=1">
                <title>EHTID Container Demo</title><style>
                body{background:#141023;color:white;font:18px sans-serif;
                display:grid;place-items:center;height:90vh;text-align:center}
                button{background:#b68bff;border:0;border-radius:16px;
                padding:20px;font-size:22px;margin:8px}
                small{color:#bdb5d7}</style></head>
                <body><main><h2>EHTID · тестовая игра</h2>
                <p>Монеты: <strong id="score">0</strong></p>
                <button id="tap">+1 монета</button>
                <button id="reset">Сбросить</button><p>
                <small>Набери монеты, закрой игру и снова запусти.
                Прогресс должен сохраниться внутри EHTID.</small></p>
                </main><script>
                var score=Number(localStorage.getItem('ehtid.demo.score')||0);
                function refresh(){document.getElementById('score').textContent=score}
                document.getElementById('tap').onclick=function(){
                  score++;localStorage.setItem('ehtid.demo.score',String(score));refresh()
                };
                document.getElementById('reset').onclick=function(){
                  score=0;localStorage.setItem('ehtid.demo.score','0');refresh()
                };refresh();</script></body></html>""".trimIndent())
            saveMeta(dir, "web", "EHTID Test — монеты")
            return mapOf("id" to id, "kind" to "web",
                "name" to "EHTID Test — монеты", "package" to "")
        } catch (error: Exception) {
            dir.deleteRecursively()
            throw error
        }
    }

    private fun displayName(uri: Uri): String {
        return context.contentResolver.query(uri,
            arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) ?: "game.zip"
            else "game.zip"
        } ?: "game.zip"
    }

    fun import(uri: Uri): Map<String, String> {
        val name = displayName(uri).substringAfterLast('/').take(120)
        val lower = name.lowercase()
        require(lower.endsWith(".zip") || lower.endsWith(".apk")) {
            "Choose HTML5 ZIP or standalone APK"
        }
        val id = UUID.randomUUID().toString()
        val dir = folder(id)
        require(dir.mkdirs())
        try {
            val isApk = lower.endsWith(".apk")
            val source = File(dir, if (isApk) "payload.apk" else "payload.zip")
            context.contentResolver.openInputStream(uri)?.use { input ->
                source.outputStream().use { output ->
                    copyBounded(input, output, maxInput)
                }
            } ?: error("Selected file cannot be read")
            if (isApk) {
                @Suppress("DEPRECATION")
                val parsed = if (Build.VERSION.SDK_INT >= 33) {
                    context.packageManager.getPackageArchiveInfo(
                        source.absolutePath,
                        PackageManager.PackageInfoFlags.of(0L))
                } else context.packageManager.getPackageArchiveInfo(
                    source.absolutePath, 0)
                val pkg = parsed?.packageName
                    ?: error("Invalid standalone APK, split APK not supported")
                saveMeta(dir, "apk", name.substringBeforeLast("."), pkg)
                return mapOf("id" to id, "kind" to "apk",
                    "name" to name.substringBeforeLast("."), "package" to pkg)
            }
            val web = File(dir, "web")
            require(web.mkdir())
            unpackWebZip(source, web)
            source.delete()
            saveMeta(dir, "web", name.substringBeforeLast("."))
            return mapOf("id" to id, "kind" to "web",
                "name" to name.substringBeforeLast("."), "package" to "")
        } catch (error: Exception) {
            dir.deleteRecursively()
            throw error
        }
    }

    private fun copyBounded(input: java.io.InputStream,
        output: java.io.OutputStream, limit: Long): Long {
        var total = 0L
        val buffer = ByteArray(32768)
        while (true) {
            val size = input.read(buffer)
            if (size < 0) break
            total += size
            require(total <= limit) { "Archive too large" }
            output.write(buffer, 0, size)
        }
        return total
    }

    private fun unpackWebZip(archive: File, root: File) {
        val prefix = root.canonicalPath + File.separator
        var unpacked = 0L
        var count = 0
        ZipInputStream(archive.inputStream().buffered()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val relative = entry.name.replace('\\', '/')
                require(!relative.startsWith("/") && !relative.contains('\u0000')) {
                    "Unsafe archive name"
                }
                val dest = File(root, relative).canonicalFile
                require(dest.path.startsWith(prefix)) { "ZIP path traversal" }
                if (entry.isDirectory) {
                    require(dest.mkdirs() || dest.isDirectory)
                } else {
                    count++
                    require(count <= 450) { "Too many files" }
                    require(dest.parentFile?.mkdirs() == true ||
                        dest.parentFile?.isDirectory == true)
                    FileOutputStream(dest).use { output ->
                        val remaining = maxExtracted - unpacked
                        require(remaining > 0) { "Unpacked ZIP too large" }
                        unpacked += copyBounded(zip, output, remaining)
                    }
                }
                zip.closeEntry()
            }
        }
        require(count > 0 && File(root, "index.html").isFile) {
            "Game ZIP must have index.html at the root"
        }
    }

    fun isWeb(id: String): Boolean = meta(id).getProperty("kind") == "web"

    fun webRoot(id: String): File {
        require(isWeb(id)) { "Not a web game" }
        return File(folder(id), "web")
    }

    fun packageName(id: String): String {
        val info = meta(id)
        require(info.getProperty("kind") == "apk") { "Not an APK" }
        return info.getProperty("package")
    }

    fun apkFile(id: String): File {
        packageName(id)
        return File(folder(id), "payload.apk").also {
            require(it.isFile) { "APK is missing" }
        }
    }

    fun remove(id: String) {
        meta(id)
        require(folder(id).deleteRecursively()) { "Cannot delete game" }
    }

    fun installApk(id: String): String {
        apkFile(id)
        if (Build.VERSION.SDK_INT >= 26 &&
            !context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}")))
            return "permission_required"
        }
        val url = Uri.parse(
            "content://${context.packageName}.containerapks/$id/payload.apk")
        val install = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(url, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(install)
        return "installer_opened"
    }

    fun launchExternalApk(id: String): String {
        val pkg = packageName(id)
        val launch = context.packageManager.getLaunchIntentForPackage(pkg)
            ?: return "not_installed_or_invisible"
        context.startActivity(launch)
        return "external_started"
    }
}

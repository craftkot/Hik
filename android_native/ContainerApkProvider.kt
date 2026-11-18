package com.ehtid.game_lab

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.FileNotFoundException

/** Read-only APK bridge to the system package installer. Not exported.
 * Only previously imported standalone APKs may be read.
 */
class ContainerApkProvider : ContentProvider() {
    private fun fileFor(uri: Uri): java.io.File {
        val parts = uri.pathSegments
        if (parts.size != 2 || parts[1] != "payload.apk") {
            throw FileNotFoundException("Invalid APK path")
        }
        return try {
            ContainerStore(requireNotNull(context)).apkFile(parts[0])
        } catch (_: Exception) {
            throw FileNotFoundException("APK not found")
        }
    }

    override fun onCreate(): Boolean = true
    override fun getType(uri: Uri): String =
        "application/vnd.android.package-archive"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Read-only APK")
        return ParcelFileDescriptor.open(fileFor(uri),
            ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(uri: Uri, projection: Array<out String>?,
        selection: String?, selectionArgs: Array<out String>?,
        sortOrder: String?): Cursor {
        val file = fileFor(uri)
        val columns = projection?.toList() ?: listOf(
            OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns.toTypedArray())
        cursor.addRow(columns.map {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> "game.apk"
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        })
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?,
        selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?,
        selection: String?, selectionArgs: Array<out String>?): Int = 0
}

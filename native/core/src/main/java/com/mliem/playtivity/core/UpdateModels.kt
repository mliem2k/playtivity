package com.mliem.playtivity.core

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset

data class AppVersion(val version: String, val buildNumber: String)

data class UpdateInfo(
    val version: String,
    val buildNumber: String,
    val buildDate: Long,
    val apkUrl: String,
    val apkFileName: String,
    val changelog: String,
    val isNightly: Boolean,
    val fileSizeBytes: Long,
)

data class UpdateCheck(val hasUpdate: Boolean, val isNightly: Boolean, val info: UpdateInfo? = null, val error: String? = null)

fun isNightlyVersion(version: String): Boolean = "-nightly-" in version

fun extractBaseVersion(version: String): String = version.substringBefore('+').substringBefore("-nightly-")

private fun compareBase(current: String, next: String): Int {
    val a = current.substringBefore('+').split('-')
    val b = next.substringBefore('+').split('-')
    val aNumbers = a.first().split('.').map { it.toIntOrNull() ?: 0 }
    val bNumbers = b.first().split('.').map { it.toIntOrNull() ?: 0 }
    for (index in 0..2) {
        val difference = (bNumbers.getOrNull(index) ?: 0).compareTo(aNumbers.getOrNull(index) ?: 0)
        if (difference != 0) return difference
    }
    if (a.size == 1 && b.size > 1) return -1
    if (a.size > 1 && b.size == 1) return 1
    return b.getOrNull(1).orEmpty().compareTo(a.getOrNull(1).orEmpty()).coerceIn(-1, 1)
}

fun isNewerVersion(current: String, next: String): Boolean = when {
    "nightly" in current && "nightly" in next -> false
    "nightly" !in current && "nightly" in next -> false
    "nightly" in current -> compareBase(extractBaseVersion(current), extractBaseVersion(next)) > 0
    else -> compareBase(current, next) > 0
}

fun shouldUpdateToNightly(current: AppVersion, nightly: UpdateInfo): Boolean {
    if ("nightly" !in current.version) {
        val currentBase = extractBaseVersion(current.version)
        val nextBase = extractBaseVersion(nightly.version)
        val currentCode = current.buildNumber.toLongOrNull()
        val nextCode = nightly.buildNumber.toLongOrNull()
        if (currentCode != null && nextCode != null && nextCode <= currentCode) return false
        return currentBase == nextBase || isNewerVersion(currentBase, nextBase)
    }
    val oldBuild = current.buildNumber.toLongOrNull()
    val newBuild = nightly.buildNumber.toLongOrNull()
    if (oldBuild != null && newBuild != null) return newBuild > oldBuild
    val oldStamp = nightlyStamp(current.version)
    val newStamp = nightlyStamp(nightly.version)
    return oldStamp != null && newStamp != null && newStamp > oldStamp
}

private fun nightlyStamp(version: String): Long? {
    val match = Regex("nightly-(\\d{4})(\\d{2})(\\d{2})-(\\d{2})(\\d{2})(\\d{2})").findAll(version).lastOrNull() ?: return null
    return runCatching {
        val parts = match.groupValues.drop(1).map(String::toInt)
        LocalDateTime.of(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).toInstant(ZoneOffset.UTC).toEpochMilli()
    }.getOrNull()
}

fun infoFromRelease(release: JSONObject, isNightly: Boolean): UpdateInfo {
    val tag = release.optString("tag_name")
    val name = release.optStringOr("name", tag)
    val body = release.optString("body")
    val lower = body.lowercase()
    val assets = release.optJSONArray("assets")
    val asset = assets?.let { list ->
        (0 until list.length()).asSequence().mapNotNull(list::optJSONObject).firstOrNull { it.optString("name").endsWith(".apk") }
    }
    val apkUrl = asset?.optString("browser_download_url").orEmpty()
    val buildDate = runCatching { Instant.parse(release.optString("published_at")).toEpochMilli() }.getOrDefault(System.currentTimeMillis())
    val version: String
    val buildNumber: String
    if (isNightly && tag.startsWith("nightly-")) {
        val full = Regex("\\*\\*version\\*\\*:\\s*`([^`]+)`").find(lower)?.groupValues?.get(1)
            ?: Regex("version:\\s*(\\S+)").find(lower)?.groupValues?.get(1)
        if (full != null) {
            version = full.substringBefore('+')
            buildNumber = full.substringAfter('+', "")
        } else {
            val base = Regex("\\*\\*base version\\*\\*:\\s*`([^`]+)`").find(lower)?.groupValues?.get(1) ?: "0.0.2"
            version = "$base-nightly-${tag.removePrefix("nightly-")}"
            buildNumber = (buildDate / 1000).toString()
        }
    } else {
        val tagVersion = tag.removePrefix("v")
        val loose = Regex("version[:\\s]+`?([^`\\s]+)").find(lower)?.groupValues?.get(1)
        version = loose?.takeIf { it.length > tagVersion.length } ?: tagVersion
        buildNumber = Regex("build number[:\\s]+`?(\\d+)").find(lower)?.groupValues?.get(1)
            ?: Regex("build\\s*(\\d+)").find(name.lowercase())?.groupValues?.get(1).orEmpty()
    }
    return UpdateInfo(version, buildNumber, buildDate, apkUrl, apkUrl.substringAfterLast('/'), body, isNightly, asset?.optLong("size") ?: 0)
}

fun checkRelease(releases: JSONArray, current: AppVersion): UpdateCheck {
    val release = newest(releases) { tag -> (tag.startsWith('v') || Regex("^\\d+\\.\\d+").containsMatchIn(tag)) && "nightly" !in tag }
        ?: return UpdateCheck(false, false, error = "No stable releases found")
    val info = infoFromRelease(release, false)
    val available = isNewerVersion(current.version, info.version)
    return UpdateCheck(available, false, if (available) info else null)
}

fun checkNightly(releases: JSONArray, current: AppVersion): UpdateCheck {
    val release = newest(releases) { it.startsWith("nightly-") }
        ?: return UpdateCheck(false, true, error = "No nightly releases found")
    val info = infoFromRelease(release, true)
    val available = shouldUpdateToNightly(current, info)
    return UpdateCheck(available, true, if (available) info else null)
}

private fun newest(releases: JSONArray, matches: (String) -> Boolean): JSONObject? =
    (0 until releases.length()).asSequence().mapNotNull(releases::optJSONObject)
        .filter { matches(it.optString("tag_name")) }
        .maxByOrNull { runCatching { Instant.parse(it.optString("published_at")).toEpochMilli() }.getOrDefault(0) }

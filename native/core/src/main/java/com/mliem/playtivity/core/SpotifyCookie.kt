package com.mliem.playtivity.core

fun spotifySessionCookie(header: String?): String? = header
    ?.split(';')
    ?.asSequence()
    ?.map(String::trim)
    ?.firstOrNull { it.startsWith("sp_dc=") }
    ?.removePrefix("sp_dc=")
    ?.takeIf(String::isNotEmpty)

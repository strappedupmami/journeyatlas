package com.atlasmasa.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val AtlasDarkScheme: ColorScheme = darkColorScheme(
    primary = Color(0xFF66C7FF),
    onPrimary = Color(0xFF002739),
    secondary = Color(0xFF6E63FF),
    tertiary = Color(0xFFFF6A4D),
    background = Color(0xFF020814),
    surface = Color(0xFF0A1224),
    onBackground = Color(0xFFE9EDF4),
    onSurface = Color(0xFFE9EDF4),
)

private val AtlasLightScheme: ColorScheme = lightColorScheme(
    primary = Color(0xFF005E8A),
    onPrimary = Color(0xFFFFFFFF),
    secondary = Color(0xFF4D3DDA),
    tertiary = Color(0xFFD4472E),
)

@Composable
fun AtlasTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) AtlasDarkScheme else AtlasLightScheme
    MaterialTheme(colorScheme = scheme, typography = MaterialTheme.typography, content = content)
}

package com.atlasmasa.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val AtlasDarkScheme: ColorScheme = darkColorScheme(
    primary = Color(0xFF8AB4F8),
    onPrimary = Color(0xFF031327),
    secondary = Color(0xFF7CC9C0),
    tertiary = Color(0xFFF5B266),
    background = Color(0xFF0F1115),
    surface = Color(0xFF171A21),
    onBackground = Color(0xFFF2F5F9),
    onSurface = Color(0xFFF2F5F9),
)

private val AtlasLightScheme: ColorScheme = lightColorScheme(
    primary = Color(0xFF1A73E8),
    onPrimary = Color(0xFFFFFFFF),
    secondary = Color(0xFF0F766E),
    tertiary = Color(0xFFB45309),
    background = Color(0xFFF7F9FC),
    surface = Color(0xFFFFFFFF),
    onBackground = Color(0xFF101828),
    onSurface = Color(0xFF101828),
)

@Composable
fun AtlasTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) AtlasDarkScheme else AtlasLightScheme
    MaterialTheme(colorScheme = scheme, typography = MaterialTheme.typography, content = content)
}

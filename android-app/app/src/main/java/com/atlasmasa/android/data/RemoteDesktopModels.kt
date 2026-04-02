package com.atlasmasa.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RemoteDesktopStatusPayload(
    @SerialName("app_name") val appName: String,
    @SerialName("device_name") val deviceName: String,
    @SerialName("runtime_status") val runtimeStatus: String,
    @SerialName("runtime_detail") val runtimeDetail: String,
    @SerialName("local_model") val localModel: String,
    @SerialName("queue_depth") val queueDepth: Int,
    @SerialName("last_action") val lastAction: String,
)

@Serializable
data class RemoteDesktopDispatchPayload(
    val prompt: String,
    val target: String,
    val route: String? = null,
)

@Serializable
data class RemoteDesktopDispatchResult(
    val message: String,
    @SerialName("queue_depth") val queueDepth: Int,
)

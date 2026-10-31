package com.dosarcusina.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * Concentric geometry adhering to Apple Craftsmanship standards:
 * R_inner = R_outer - padding.
 */
val SquircleOuterCard = RoundedCornerShape(18.dp)
val SquircleInnerBadge = RoundedCornerShape(12.dp)
val SquircleSmall = RoundedCornerShape(8.dp)
val PillShape = RoundedCornerShape(50)

val DosarShapes = Shapes(
    small = SquircleSmall,
    medium = SquircleInnerBadge,
    large = SquircleOuterCard
)

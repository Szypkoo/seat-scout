plugins {
    id("com.android.application") version "8.7.2" apply false
    id("com.android.library") version "8.7.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.0" apply false
}

subprojects {
    apply(plugin = "org.jetbrains.kotlin.android")

    tasks.withType<com.android.build.gradle.internal.tasks.CheckAarMetadataTask>().configureEach {
        enabled = false
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompilationTask<*>>().configureEach {
        compilerOptions {
            suppressWarnings.set(true)
            freeCompilerArgs.addAll(
                "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
                "-opt-in=androidx.compose.material.ExperimentalMaterialApi",
                "-opt-in=kotlin.RequiresOptIn",
                "-Xskip-metadata-version-check"
            )
        }
    }
}

project(":SkipUI") {
    tasks.matching { it.name.startsWith("compile") && it.name.endsWith("Kotlin") }.configureEach {
        doFirst {
            val imageKt = file("${projectDir}/src/main/kotlin/skip/ui/Image.kt")
            if (imageKt.exists()) {
                var content = imageKt.readText()
                var modified = false

                val oldFallback = "Icon(imageVector = Icons.Default.Warning, contentDescription = \"missing icon\")"
                val newFallback = "Box(modifier = Modifier.size(20.dp))"
                if (content.contains(oldFallback)) {
                    content = content.replace(oldFallback, newFallback)
                    modified = true
                }

                val symbolTarget = "\"exclamationmark.triangle.fill\" -> return \"Icons.Filled.Warning\""
                val extraSymbols = """
                "bolt.fill", "bolt" -> return "Icons.Filled.Bolt"
                "point.topleft.down.to.point.bottomright.curvepath" -> return "Icons.Filled.AltRoute"
                "chair.lounge.fill", "chair.lounge", "chair" -> return "Icons.Filled.EventSeat"
                "terminal.fill", "terminal" -> return "Icons.Filled.Terminal"
                "circle.fill" -> return "Icons.Filled.Circle"
                "circle" -> return "Icons.Outlined.Circle"
                "flag.checkered" -> return "Icons.Outlined.Flag"
                "flag.checkered.circle.fill" -> return "Icons.Filled.Flag"
                "arrow.up.arrow.down" -> return "Icons.Outlined.SwapVert"
                "tram.fill", "tram", "train.side.front.car" -> return "Icons.Filled.Train"
                "arrow.clockwise" -> return "Icons.Outlined.Refresh"
                "doc.on.doc" -> return "Icons.Outlined.ContentCopy"
                "arrow.left.and.right" -> return "Icons.Outlined.CompareArrows"
                "rectangle.portrait.lefthalf.filled" -> return "Icons.Outlined.CropPortrait"
                "figure.roll" -> return "Icons.Filled.Accessible"
                "figure.stand" -> return "Icons.Filled.Accessibility"
                "xmark.circle.fill" -> return "Icons.Filled.Cancel"
                "arrow.right.circle.fill" -> return "Icons.Filled.ArrowCircleRight"
                "clock.arrow.circlepath" -> return "Icons.Outlined.History"
                "arrow.right" -> return "Icons.Outlined.ArrowForward"
                "arrow.up" -> return "Icons.Outlined.ArrowUpward"
                "arrow.down" -> return "Icons.Outlined.ArrowDownward"
                "toilet.fill" -> return "Icons.Filled.Wc"
                "suitcase.fill" -> return "Icons.Filled.Luggage"
                "bicycle" -> return "Icons.Filled.DirectionsBike"
                "fork.knife" -> return "Icons.Filled.Restaurant"
                "exclamationmark.bubble.fill" -> return "Icons.Filled.Feedback"
                "star" -> return "Icons.Outlined.Star"
                """.trimIndent()

                if (!content.contains("\"bolt.fill\"") && content.contains(symbolTarget)) {
                    content = content.replace(symbolTarget, "$symbolTarget\n                $extraSymbols")
                    modified = true
                }

                val vectorOutlinedTarget = "\"Icons.Outlined.Warning\" -> return Icons.Outlined.Warning.sref()"
                val extraOutlined = """
                "Icons.Outlined.Circle" -> return Icons.Outlined.Circle.sref()
                "Icons.Outlined.Flag" -> return Icons.Outlined.Flag.sref()
                "Icons.Outlined.SwapVert" -> return Icons.Outlined.SwapVert.sref()
                "Icons.Outlined.ContentCopy" -> return Icons.Outlined.ContentCopy.sref()
                "Icons.Outlined.CompareArrows" -> return Icons.Outlined.CompareArrows.sref()
                "Icons.Outlined.CropPortrait" -> return Icons.Outlined.CropPortrait.sref()
                "Icons.Outlined.History" -> return Icons.Outlined.History.sref()
                "Icons.Outlined.ArrowUpward" -> return Icons.Outlined.ArrowUpward.sref()
                "Icons.Outlined.ArrowDownward" -> return Icons.Outlined.ArrowDownward.sref()
                """.trimIndent()

                if (!content.contains("\"Icons.Outlined.Circle\"") && content.contains(vectorOutlinedTarget)) {
                    content = content.replace(vectorOutlinedTarget, "$vectorOutlinedTarget\n                $extraOutlined")
                    modified = true
                }

                val vectorFilledTarget = "\"Icons.Filled.Warning\" -> return Icons.Filled.Warning.sref()"
                val extraFilled = """
                "Icons.Filled.Bolt" -> return Icons.Filled.Bolt.sref()
                "Icons.Filled.AltRoute" -> return Icons.Filled.AltRoute.sref()
                "Icons.Filled.EventSeat" -> return Icons.Filled.EventSeat.sref()
                "Icons.Filled.Terminal" -> return Icons.Filled.Terminal.sref()
                "Icons.Filled.Circle" -> return Icons.Filled.Circle.sref()
                "Icons.Filled.Flag" -> return Icons.Filled.Flag.sref()
                "Icons.Filled.Train" -> return Icons.Filled.Train.sref()
                "Icons.Filled.Accessible" -> return Icons.Filled.Accessible.sref()
                "Icons.Filled.Accessibility" -> return Icons.Filled.Accessibility.sref()
                "Icons.Filled.Cancel" -> return Icons.Filled.Cancel.sref()
                "Icons.Filled.ArrowCircleRight" -> return Icons.Filled.ArrowCircleRight.sref()
                "Icons.Filled.Wc" -> return Icons.Filled.Wc.sref()
                "Icons.Filled.Luggage" -> return Icons.Filled.Luggage.sref()
                "Icons.Filled.DirectionsBike" -> return Icons.Filled.DirectionsBike.sref()
                "Icons.Filled.Restaurant" -> return Icons.Filled.Restaurant.sref()
                "Icons.Filled.Feedback" -> return Icons.Filled.Feedback.sref()
                """.trimIndent()

                if (!content.contains("\"Icons.Filled.Bolt\"") && content.contains(vectorFilledTarget)) {
                    content = content.replace(vectorFilledTarget, "$vectorFilledTarget\n                $extraFilled")
                    modified = true
                }

                if (modified) {
                    imageKt.writeText(content)
                }
            }
        }
    }
}

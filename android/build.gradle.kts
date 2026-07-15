import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// -----------------------------------------------------------------------
// Workaround for a known upstream defect in file_picker (11.0.0 - 11.0.2):
// the plugin's own android/build.gradle applies `com.android.library` but
// never applies the Kotlin Android plugin, even though all of its sources
// are .kt files. That means file_picker's Kotlin sources are never
// compiled, so FilePickerPlugin.class does not exist when
// GeneratedPluginRegistrant.java (which correctly references it) is
// compiled -> "cannot find symbol". Tracked upstream at:
// https://github.com/miguelpruivo/flutter_file_picker/issues/1973
// A maintainer-confirmed fix landed in 11.0.1, but is still being reported
// as reoccurring with newer AGP/Gradle by some users on 11.0.2. Rather than
// patch the immutable, shared pub-cache copy of the plugin (which would be
// silently lost on every `flutter pub get` / CI checkout, and which we've
// been asked not to touch), we defensively apply the Kotlin Android plugin
// to the file_picker subproject from the app's own build, reusing the same
// Kotlin version already resolved via `pluginManagement` in
// settings.gradle.kts. This becomes a harmless no-op once the upstream fix
// is fully effective for this exact AGP/Kotlin combination.
//
// NOTE on lifecycle: this must NOT be done via `subprojects { afterEvaluate
// { ... } }`. The `evaluationDependsOn(":app")` call above forces plugin
// subprojects (including file_picker) to evaluate ahead of the normal
// configuration order, so by the time a `subprojects { afterEvaluate {} }`
// block further down the script runs, file_picker may already be fully
// evaluated -> "Cannot run Project.afterEvaluate(Action) when the project
// is already evaluated." `gradle.beforeProject` is evaluation-order-safe:
// it fires once, before each project's own build script is evaluated, so
// it can never race against `evaluationDependsOn` or any other project's
// evaluation state.
//
// Second, related defect: once file_picker's Kotlin sources are actually
// compiled, its Java target stays at 17 (AGP 9's default, matching the
// rest of this app), but the newly-applied Kotlin Android plugin has no
// jvmTarget of its own configured (file_picker's build.gradle never sets
// one), so the Kotlin compiler falls back to the JDK Gradle itself is
// running on - JVM 21 in this environment. That produces:
// ":file_picker:compileDebugKotlin ... Inconsistent JVM Target
// Compatibility. Java target = 17, Kotlin target = 21."
// We pin file_picker's Kotlin compile tasks to JVM 17 - the same target
// already used by the app module (see app/build.gradle.kts) - via
// `tasks.withType<KotlinCompile>().configureEach { ... }`, which is safe
// to call from `beforeProject` because it's a lazy/deferred registration:
// it configures the tasks whenever they end up being created, rather than
// requiring them to already exist.
gradle.beforeProject {
    if (name == "file_picker") {
        if (!plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

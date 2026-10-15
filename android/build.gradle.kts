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
// Some Flutter plugins (e.g. file_picker, share_plus) still compile against
// an older Android API, while newer Flutter plugins they depend on need
// API 36. Build every plugin against API 36. This does not change the
// app's minSdk / targetSdk (which phones it installs on).
// Must stay ABOVE the evaluationDependsOn(":app") block.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.api.dsl.LibraryExtension) {
            androidExt.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

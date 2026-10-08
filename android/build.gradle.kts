import org.gradle.api.tasks.compile.JavaCompile
import org.gradle.api.tasks.Delete
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

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
    val newSubprojectBuildDir: Directory =
        newBuildDir.dir(project.name)

    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    fun configureJvmTarget(proj: Project) {
        proj.tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
            
            // SILENCE WARNINGS: Suppress all deprecation and unchecked warnings from third-party Java plugins
            options.isWarnings = false
            options.compilerArgs.addAll(listOf("-Xlint:none", "-nowarn"))
        }
        proj.tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
            }
        }
    }

    fun configureAndroidSdk(proj: Project) {
        proj.plugins.withId("com.android.library") {
            proj.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                compileSdk = 36
            }
        }
    }

    if (state.executed) {
        configureJvmTarget(this)
        configureAndroidSdk(this)
    } else {
        afterEvaluate {
            configureJvmTarget(this)
            configureAndroidSdk(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
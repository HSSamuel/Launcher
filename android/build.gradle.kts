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
        }
        proj.tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
            }
        }
        
        // CHANGED: Intercept 3rd-party plugins and force them to SDK 36
        val androidExt = proj.extensions.findByName("android")
        if (androidExt != null) {
            try {
                androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.java).invoke(androidExt, 36) // UPGRADED TO 36
            } catch (e: Exception) { }
            try {
                androidExt.javaClass.getMethod("setCompileSdk", Int::class.java).invoke(androidExt, 36) // UPGRADED TO 36
            } catch (e: Exception) { }
        }
    }

    if (state.executed) {
        configureJvmTarget(this)
    } else {
        afterEvaluate {
            configureJvmTarget(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
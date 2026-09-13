function templateCategories() {
    return [
        { id: "all", title: "All" },
        { id: "starter", title: "Starter" },
        { id: "cms", title: "CMS" },
        { id: "framework", title: "Framework" }
    ]
}

function templates() {
    return [
        { id: "empty", title: "Empty", icon: "icons/projects/existing-project.svg", category: "starter", mode: "basic", frameworkPreset: "custom", webRoot: ".", createStarter: true },
        { id: "custom", title: "Custom Site", icon: "icons/projects/express.svg", category: "starter", mode: "custom", frameworkPreset: "custom", webRoot: ".", createStarter: true },
        { id: "wordpress", title: "WordPress", icon: "icons/projects/vue.svg", category: "cms", mode: "wordpress", frameworkPreset: "wordpress", webRoot: ".", createDatabase: true },
        { id: "drupal", title: "Drupal", icon: "icons/projects/nextjs.svg", category: "cms", mode: "composer", frameworkPreset: "drupal", webRoot: "web", composerPackage: "drupal/recommended-project" },
        { id: "laravel", title: "Laravel", icon: "icons/projects/remix.svg", category: "framework", mode: "laravel", frameworkPreset: "laravel", webRoot: "public", createDatabase: false },
        { id: "symfony", title: "Symfony", icon: "icons/projects/nuxt.svg", category: "framework", mode: "composer", frameworkPreset: "symfony", webRoot: "public", composerPackage: "symfony/skeleton" },
        { id: "cakephp", title: "CakePHP", icon: "icons/projects/vue.svg", category: "framework", mode: "composer", frameworkPreset: "cakephp", webRoot: "webroot", composerPackage: "cakephp/app" },
        { id: "codeigniter4", title: "CodeIgniter 4", icon: "icons/projects/express.svg", category: "framework", mode: "composer", frameworkPreset: "codeigniter", webRoot: "public", composerPackage: "codeigniter4/appstarter" },
        { id: "yii", title: "Yii", icon: "icons/projects/svelte.svg", category: "framework", mode: "composer", frameworkPreset: "yii", webRoot: "web", composerPackage: "yiisoft/yii2-app-basic" },
        { id: "slim", title: "Slim", icon: "icons/projects/sveltekit.svg", category: "framework", mode: "composer", frameworkPreset: "slim", webRoot: "public", composerPackage: "slim/slim" },
        { id: "laminas", title: "Laminas", icon: "icons/projects/nestjs.svg", category: "framework", mode: "composer", frameworkPreset: "laminas", webRoot: "public", composerPackage: "laminas/laminas-mvc-skeleton" }
    ]
}

function templateById(templateId) {
    var list = templates()
    for (var i = 0; i < list.length; i++) {
        if (String(list[i].id || "") === String(templateId || "")) {
            return list[i]
        }
    }
    return null
}

function templatesForCategory(categoryId) {
    var list = templates()
    var category = String(categoryId || "all")
    if (category === "all") {
        return list
    }
    var filtered = []
    for (var i = 0; i < list.length; i++) {
        if (String(list[i].category || "") === category) {
            filtered.push(list[i])
        }
    }
    return filtered
}

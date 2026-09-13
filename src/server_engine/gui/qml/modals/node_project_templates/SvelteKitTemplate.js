function template() {
    return {
        id: "sveltekit",
        title: "SvelteKit",
        icon: "../icons/projects/sveltekit.svg",
        description: "SvelteKit app with routing.",
        runtimeType: "fullstack",
        minNodeVersion: "18.18.0",
        recommendedNodeVersion: "20.0.0",
        installCommand: "npm install",
        createCommand: "npm create svelte@latest",
        devCommand: "npm run dev",
        buildCommand: "npm run build",
        defaultPort: "3000"
    }
}

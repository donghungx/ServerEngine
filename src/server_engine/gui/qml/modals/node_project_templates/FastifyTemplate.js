function template() {
    return {
        id: "fastify",
        title: "Fastify API",
        icon: "../icons/projects/fastify.svg",
        description: "Fast and lightweight API service.",
        runtimeType: "api",
        minNodeVersion: "16.0.0",
        recommendedNodeVersion: "18.0.0",
        installCommand: "npm install fastify nodemon",
        createCommand: "npm init -y",
        devCommand: "nodemon server.js",
        buildCommand: "",
        defaultPort: "3001"
    }
}

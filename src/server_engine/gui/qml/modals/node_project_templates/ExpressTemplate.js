function template() {
    return {
        id: "express",
        title: "Express API",
        icon: "../icons/projects/express.svg",
        description: "Express backend API.",
        runtimeType: "api",
        minNodeVersion: "16.0.0",
        recommendedNodeVersion: "18.0.0",
        installCommand: "npm install express",
        createCommand: "npm init -y",
        devCommand: "nodemon server.js",
        buildCommand: "",
        defaultPort: "3001"
    }
}

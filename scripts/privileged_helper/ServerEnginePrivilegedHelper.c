#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static const char *k_helper_socket_path = "/var/run/com.serverengine.app.helper.sock";

static void fatal(const char *message) {
    fprintf(stderr, "ERROR: %s\n", message);
    exit(EXIT_FAILURE);
}

static void format_errno_message(char *buffer, size_t size, const char *prefix) {
    snprintf(buffer, size, "%s: %s", prefix, strerror(errno));
}

static bool write_all(int fd, const void *data, size_t size) {
    const unsigned char *ptr = (const unsigned char *)data;
    size_t written = 0;
    while (written < size) {
        ssize_t result = write(fd, ptr + written, size - written);
        if (result < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        written += (size_t)result;
    }
    return true;
}

static char *dup_cstring(const char *value) {
    if (value == NULL) {
        return NULL;
    }
    size_t length = strlen(value);
    char *copy = (char *)malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, value, length + 1);
    return copy;
}

static char *json_escape(const char *input) {
    if (input == NULL) {
        return dup_cstring("");
    }

    size_t extra = 0;
    for (const unsigned char *p = (const unsigned char *)input; *p != '\0'; ++p) {
        switch (*p) {
            case '\\':
            case '"':
            case '\n':
            case '\r':
            case '\t':
                extra += 1;
                break;
            default:
                break;
        }
    }

    size_t length = strlen(input);
    char *out = (char *)malloc(length + extra + 1);
    if (out == NULL) {
        return NULL;
    }

    char *dst = out;
    for (const unsigned char *p = (const unsigned char *)input; *p != '\0'; ++p) {
        switch (*p) {
            case '\\':
                *dst++ = '\\';
                *dst++ = '\\';
                break;
            case '"':
                *dst++ = '\\';
                *dst++ = '"';
                break;
            case '\n':
                *dst++ = '\\';
                *dst++ = 'n';
                break;
            case '\r':
                *dst++ = '\\';
                *dst++ = 'r';
                break;
            case '\t':
                *dst++ = '\\';
                *dst++ = 't';
                break;
            default:
                *dst++ = (char)*p;
                break;
        }
    }
    *dst = '\0';
    return out;
}

static char *json_get_string(const char *json, const char *key) {
    if (json == NULL || key == NULL) {
        return NULL;
    }

    char pattern[128];
    if (snprintf(pattern, sizeof(pattern), "\"%s\"", key) < 0) {
        return NULL;
    }

    const char *p = strstr(json, pattern);
    if (p == NULL) {
        return NULL;
    }

    p += strlen(pattern);
    while (*p != '\0' && isspace((unsigned char)*p)) {
        ++p;
    }
    if (*p != ':') {
        return NULL;
    }
    ++p;
    while (*p != '\0' && isspace((unsigned char)*p)) {
        ++p;
    }
    if (*p != '"') {
        return NULL;
    }
    ++p;

    size_t capacity = strlen(p) + 1;
    char *out = (char *)malloc(capacity);
    if (out == NULL) {
        return NULL;
    }

    size_t out_index = 0;
    while (*p != '\0') {
        if (*p == '"') {
            break;
        }
        if (*p == '\\') {
            ++p;
            if (*p == '\0') {
                break;
            }
            switch (*p) {
                case '"': out[out_index++] = '"'; break;
                case '\\': out[out_index++] = '\\'; break;
                case '/': out[out_index++] = '/'; break;
                case 'b': out[out_index++] = '\b'; break;
                case 'f': out[out_index++] = '\f'; break;
                case 'n': out[out_index++] = '\n'; break;
                case 'r': out[out_index++] = '\r'; break;
                case 't': out[out_index++] = '\t'; break;
                default: out[out_index++] = *p; break;
            }
            ++p;
            continue;
        }
        out[out_index++] = *p;
        ++p;
    }
    out[out_index] = '\0';
    return out;
}

static const char *validated_hosts_path(const char *raw_path) {
    if (raw_path == NULL || raw_path[0] == '\0') {
        return "/etc/hosts";
    }
    if (strcmp(raw_path, "/etc/hosts") != 0) {
        return NULL;
    }
    return raw_path;
}

static int require_effective_root(char *error_buffer, size_t error_size) {
    if (geteuid() != 0) {
        snprintf(error_buffer, error_size, "Helper must run with effective UID 0.");
        return -1;
    }
    if (setuid(0) != 0) {
        format_errno_message(error_buffer, error_size, "Unable to promote helper real UID");
        return -1;
    }
    return 0;
}

static int copy_file(const char *input_path, const char *output_path, char *error_buffer, size_t error_size) {
    int input_fd = open(input_path, O_RDONLY);
    if (input_fd < 0) {
        format_errno_message(error_buffer, error_size, "Unable to read pending hosts content");
        return -1;
    }

    int output_fd = open(output_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (output_fd < 0) {
        format_errno_message(error_buffer, error_size, "Unable to write /etc/hosts");
        close(input_fd);
        return -1;
    }

    unsigned char buffer[64 * 1024];
    for (;;) {
        ssize_t bytes_read = read(input_fd, buffer, sizeof(buffer));
        if (bytes_read < 0) {
            if (errno == EINTR) {
                continue;
            }
            format_errno_message(error_buffer, error_size, "Unable to read pending hosts content");
            close(input_fd);
            close(output_fd);
            return -1;
        }
        if (bytes_read == 0) {
            break;
        }

        size_t written = 0;
        while (written < (size_t)bytes_read) {
            ssize_t result = write(output_fd, buffer + written, (size_t)bytes_read - written);
            if (result < 0) {
                if (errno == EINTR) {
                    continue;
                }
                format_errno_message(error_buffer, error_size, "Unable to write /etc/hosts");
                close(input_fd);
                close(output_fd);
                return -1;
            }
            written += (size_t)result;
        }
    }

    if (fsync(output_fd) != 0) {
        format_errno_message(error_buffer, error_size, "Unable to sync /etc/hosts");
        close(input_fd);
        close(output_fd);
        return -1;
    }

    close(input_fd);
    close(output_fd);
    return 0;
}

static int run_command(const char *executable, char *const argv[], char *error_buffer, size_t error_size) {
    pid_t pid = 0;
    int spawn_result = posix_spawn(&pid, executable, NULL, NULL, argv, environ);
    if (spawn_result != 0) {
        errno = spawn_result;
        format_errno_message(error_buffer, error_size, "Failed to run command");
        return -1;
    }

    int status = 0;
    for (;;) {
        if (waitpid(pid, &status, 0) < 0) {
            if (errno == EINTR) {
                continue;
            }
            format_errno_message(error_buffer, error_size, "Failed to wait for command");
            return -1;
        }
        break;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        snprintf(error_buffer, error_size, "Command failed: %s", executable);
        return -1;
    }
    return 0;
}

static int flush_dns(char *error_buffer, size_t error_size) {
    char *const flushcache_argv[] = {(char *)"/usr/bin/dscacheutil", (char *)"-flushcache", NULL};
    char *const hup_argv[] = {(char *)"/usr/bin/killall", (char *)"-HUP", (char *)"mDNSResponder", NULL};
    if (run_command("/usr/bin/dscacheutil", flushcache_argv, error_buffer, error_size) != 0) {
        return -1;
    }
    if (run_command("/usr/bin/killall", hup_argv, error_buffer, error_size) != 0) {
        return -1;
    }
    return 0;
}

static void write_response(int fd, bool ok, const char *message) {
    char *escaped = json_escape(message != NULL ? message : "");
    if (escaped == NULL) {
        const char fallback[] = "{\"ok\":false,\"message\":\"encode failed\"}\n";
        (void)write_all(fd, fallback, sizeof(fallback) - 1);
        return;
    }

    const char *prefix = ok ? "{\"ok\":true,\"message\":\"" : "{\"ok\":false,\"message\":\"";
    const char *suffix = "\"}\n";
    size_t response_size = strlen(prefix) + strlen(escaped) + strlen(suffix);
    char *response = (char *)malloc(response_size + 1);
    if (response == NULL) {
        free(escaped);
        const char fallback[] = "{\"ok\":false,\"message\":\"encode failed\"}\n";
        (void)write_all(fd, fallback, sizeof(fallback) - 1);
        return;
    }

    snprintf(response, response_size + 1, "%s%s%s", prefix, escaped, suffix);
    (void)write_all(fd, response, response_size);
    free(response);
    free(escaped);
}

static void process_client(int client_fd) {
    char buffer[8192];
    ssize_t bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
    if (bytes_read <= 0) {
        write_response(client_fd, false, "Empty request.");
        return;
    }
    buffer[bytes_read] = '\0';

    char *command = json_get_string(buffer, "command");
    if (command == NULL) {
        write_response(client_fd, false, "Invalid request: missing command.");
        return;
    }

    char error_buffer[512];
    error_buffer[0] = '\0';

    if (strcmp(command, "write-hosts") == 0) {
        if (require_effective_root(error_buffer, sizeof(error_buffer)) != 0) {
            write_response(client_fd, false, error_buffer);
            free(command);
            return;
        }

        char *input_path = json_get_string(buffer, "input");
        char *hosts_path_raw = json_get_string(buffer, "hosts_path");
        if (input_path == NULL || input_path[0] == '\0') {
            write_response(client_fd, false, "write-hosts requires input.");
            free(command);
            free(input_path);
            free(hosts_path_raw);
            return;
        }

        const char *hosts_path = validated_hosts_path(hosts_path_raw);
        if (hosts_path == NULL) {
            write_response(client_fd, false, "Refusing write outside /etc/hosts.");
            free(command);
            free(input_path);
            free(hosts_path_raw);
            return;
        }

        if (copy_file(input_path, hosts_path, error_buffer, sizeof(error_buffer)) != 0) {
            write_response(client_fd, false, error_buffer);
            free(command);
            free(input_path);
            free(hosts_path_raw);
            return;
        }

        if (flush_dns(error_buffer, sizeof(error_buffer)) != 0) {
            write_response(client_fd, false, error_buffer);
            free(command);
            free(input_path);
            free(hosts_path_raw);
            return;
        }

        write_response(client_fd, true, "Hosts file updated.");
        free(command);
        free(input_path);
        free(hosts_path_raw);
        return;
    }

    if (strcmp(command, "flush-dns") == 0) {
        if (require_effective_root(error_buffer, sizeof(error_buffer)) != 0) {
            write_response(client_fd, false, error_buffer);
            free(command);
            return;
        }
        if (flush_dns(error_buffer, sizeof(error_buffer)) != 0) {
            write_response(client_fd, false, error_buffer);
            free(command);
            return;
        }
        write_response(client_fd, true, "DNS cache flushed.");
        free(command);
        return;
    }

    char invalid_message[256];
    snprintf(invalid_message, sizeof(invalid_message), "Unknown command: %s", command);
    write_response(client_fd, false, invalid_message);
    free(command);
}

static int run_server(void) {
    if (geteuid() != 0) {
        fatal("Helper must run with effective UID 0.");
    }
    if (setuid(0) != 0) {
        char error_buffer[512];
        format_errno_message(error_buffer, sizeof(error_buffer), "Unable to promote helper real UID");
        fatal(error_buffer);
    }

    (void)unlink(k_helper_socket_path);

    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        fatal("Unable to create helper socket");
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    size_t path_length = strlen(k_helper_socket_path);
    if (path_length >= sizeof(addr.sun_path)) {
        close(server_fd);
        fatal("Socket path too long.");
    }
    memcpy(addr.sun_path, k_helper_socket_path, path_length + 1);

    socklen_t addr_len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + path_length + 1);
    if (bind(server_fd, (struct sockaddr *)&addr, addr_len) != 0) {
        int saved_errno = errno;
        close(server_fd);
        errno = saved_errno;
        fatal("Unable to bind helper socket");
    }

    if (chmod(k_helper_socket_path, 0666) != 0) {
        int saved_errno = errno;
        close(server_fd);
        errno = saved_errno;
        fatal("Unable to set helper socket permissions");
    }

    if (listen(server_fd, 16) != 0) {
        int saved_errno = errno;
        close(server_fd);
        errno = saved_errno;
        fatal("Unable to listen on helper socket");
    }

    for (;;) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            if (errno == EINTR) {
                continue;
            }
            continue;
        }
        process_client(client_fd);
        close(client_fd);
    }
}

int main(void) {
    if (run_server() != 0) {
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}

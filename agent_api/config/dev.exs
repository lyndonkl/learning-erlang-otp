import Config

# For development, we disable any cache and enable
# debugging and code reloading.
config :agent_api, AgentApiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_that_is_at_least_64_characters_long_for_security",
  watchers: []

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# libcluster topology for development
# Gossip strategy automatically discovers nodes on the same network
config :libcluster,
  topologies: [
    agent_cluster: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_if: "127.0.0.1",
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1
      ]
    ]
  ]

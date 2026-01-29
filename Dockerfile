# Dockerfile for testing schmooze with multiple Ruby versions
ARG RUBY_VERSION=3.3

FROM ruby:${RUBY_VERSION}

# Install Node.js (required for schmooze tests)
RUN apt-get update -qq && \
    apt-get install -y nodejs npm && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install bundler (version depends on Ruby version)
# Ruby < 3.2 requires bundler <= 2.4.x
ARG RUBY_VERSION
RUN if echo "${RUBY_VERSION}" | grep -qE "^(2\.[67]|3\.[01])"; then \
      gem install bundler -v 2.4.22; \
    else \
      gem install bundler; \
    fi

# Default command
CMD ["bundle", "exec", "rake", "test"]

# Comprehensive Testing Guide for Elixir Projects

**Purpose:** A practical guide to testing Elixir applications with dependency injection, error path coverage, CI/CD integration, and parallel execution.

**Target Audience:** Developers and LLMs implementing testable Elixir code

---

## Table of Contents

1. [Core Technologies](#core-technologies)
2. [Testing Tiers Strategy](#testing-tiers-strategy)
3. [Dependency Injection Pattern](#dependency-injection-pattern)
4. [Testing Error Paths](#testing-error-paths)
5. [CI/CD Configuration](#cicd-configuration)
6. [Parallel Test Execution](#parallel-test-execution)
7. [Mock Implementation Patterns](#mock-implementation-patterns)
8. [Complete Example](#complete-example)
9. [LLM Prompts](#llm-prompts)

---

## Core Technologies

### **ExUnit** - Elixir's Built-In Test Framework

**What it is:** The standard testing library that ships with Elixir.

**Location:** Built into Elixir - no installation needed.

**Basic usage:**
```elixir
# test/my_module_test.exs
defmodule MyModuleTest do
  use ExUnit.Case, async: true  # async: true enables parallel execution

  test "basic assertion" do
    assert 1 + 1 == 2
  end
end
```

**Run tests:**
```bash
mix test                    # Run all tests
mix test test/specific_test.exs   # Run one file
mix test --only integration # Run tagged tests
mix test --exclude slow     # Exclude tagged tests
```

**Key features:**
- Built-in assertions (`assert`, `refute`, `assert_raise`)
- Test tagging (`@tag :integration`, `@tag :unit`)
- Async execution (`async: true`)
- Descriptive test blocks (`describe` blocks)
- Setup/teardown hooks (`setup`, `on_exit`)

---

### **Mix** - Elixir's Build Tool

**What it is:** Elixir's project management and build tool.

**Key testing features:**

```bash
# Test configuration
MIX_ENV=test mix test           # Use test environment
mix test --trace                # Run tests synchronously with detailed output
mix test --stale                # Run only tests whose modules changed
mix test --failed               # Re-run only failed tests
mix test --max-failures 5       # Stop after 5 failures
```

**Environment configuration:**
```elixir
# config/test.exs
import Config

config :my_app,
  repository: MyApp.Mocks.GitRepository,  # Use mocks in test
  terminal: MyApp.Mocks.Terminal
```

---

### **Behaviours** - Elixir's Interface Pattern

**What it is:** Compile-time contracts that define function signatures.

**Why use it:** Enables dependency injection with compile-time verification.

```elixir
# Define the contract (port)
defmodule MyApp.Ports.Repository do
  @callback fetch_data(id :: integer()) :: {:ok, term()} | {:error, term()}
  @callback save_data(data :: term()) :: :ok | {:error, term()}
end

# Real implementation
defmodule MyApp.Adapters.DatabaseRepository do
  @behaviour MyApp.Ports.Repository

  @impl true  # Compiler verifies this function exists in behaviour
  def fetch_data(id) do
    # Real database query
    DB.query("SELECT * FROM items WHERE id = ?", [id])
  end

  @impl true
  def save_data(data) do
    # Real database insert
    DB.insert("items", data)
  end
end

# Mock implementation
defmodule MyApp.Mocks.Repository do
  @behaviour MyApp.Ports.Repository

  @impl true
  def fetch_data(_id) do
    {:ok, %{id: 1, name: "test"}}  # Return fake data
  end

  @impl true
  def save_data(_data) do
    :ok  # Pretend save succeeded
  end
end
```

**Compiler verification:**
If you forget to implement a callback, compilation fails:
```
warning: function save_data/1 required by behaviour MyApp.Ports.Repository
is not implemented (in module MyApp.Mocks.Repository)
```

---

## Testing Tiers Strategy

### **Tier 1: Integration Tests (Most Important)**

**Purpose:** Test with real dependencies (databases, file systems, external APIs).

**When to use:** Happy path, critical workflows, end-to-end scenarios.

**Characteristics:**
- Use real implementations
- Run locally and in pre-commit hooks
- Slower but high confidence
- Tag with `@tag :integration`

```elixir
@tag :integration
test "user registration creates database record" do
  # Uses REAL database
  assert {:ok, user} = UserService.register("alice@example.com")
  assert DB.exists?(:users, user.id)  # Real DB query
end
```

---

### **Tier 2: Unit Tests (Error Paths)**

**Purpose:** Test error handling, edge cases, and branches that are hard to trigger with real dependencies.

**When to use:** Error paths, validation logic, business rules.

**Characteristics:**
- Use mocked dependencies
- Run everywhere (CI, Docker, locally)
- Fast and reliable
- Tag with `@tag :unit`

```elixir
@tag :unit
test "handles database connection failure gracefully" do
  # Use MOCK that returns error
  mock_db = fn -> {:error, :connection_refused} end

  assert {:error, :unavailable} = UserService.register("alice@example.com", db: mock_db)
end
```

---

### **Tier 3: Property Tests (Optional)**

**Purpose:** Test properties with randomized inputs (fuzzing).

**Library:** StreamData (separate package)

```elixir
use ExUnitProperties

property "parsing never crashes" do
  check all input <- StreamData.string(:printable) do
    # Should never raise, even with garbage input
    assert {:ok, _} = Parser.parse(input) or match?({:error, _}, Parser.parse(input))
  end
end
```

---

## Dependency Injection Pattern

### **The Problem: Hardcoded Dependencies**

```elixir
defmodule UserService do
  def register(email) do
    # Hardcoded dependency - cannot test without real database!
    case Database.insert(:users, %{email: email}) do
      {:ok, user} -> send_welcome_email(user)  # Also hardcoded!
      error -> error
    end
  end
end
```

**Testing problems:**
- ❌ Cannot test without real database
- ❌ Cannot test email sending failure
- ❌ Cannot run tests in parallel (database conflicts)
- ❌ Tests fail in CI without database

---

### **The Solution: Dependency Injection**

```elixir
defmodule UserService do
  # Accept dependencies as options with sensible defaults
  def register(email, opts \\ []) do
    database = Keyword.get(opts, :database, MyApp.Adapters.Database)
    mailer = Keyword.get(opts, :mailer, MyApp.Adapters.Mailer)

    case database.insert(:users, %{email: email}) do
      {:ok, user} -> mailer.send_welcome(user)
      error -> error
    end
  end
end
```

**Benefits:**
- ✅ Production uses real database (default)
- ✅ Tests can inject mocks
- ✅ No environment-specific code
- ✅ Works anywhere (CI, Docker, etc.)

**Usage:**
```elixir
# Production code - uses defaults
UserService.register("alice@example.com")

# Test code - injects mocks
UserService.register("alice@example.com",
  database: MockDatabase,
  mailer: MockMailer
)
```

---

### **Configuration-Based Injection (Alternative)**

For app-wide configuration:

```elixir
# config/config.exs (production)
config :my_app,
  database: MyApp.Adapters.PostgresDB,
  mailer: MyApp.Adapters.SendGrid

# config/test.exs (test environment)
config :my_app,
  database: MyApp.Mocks.Database,
  mailer: MyApp.Mocks.Mailer
```

**Code:**
```elixir
defmodule UserService do
  def register(email) do
    database = Application.get_env(:my_app, :database)
    mailer = Application.get_env(:my_app, :mailer)

    # Use configured adapters
    case database.insert(:users, %{email: email}) do
      {:ok, user} -> mailer.send_welcome(user)
      error -> error
    end
  end
end
```

**Trade-off:** Global config vs. explicit parameters. Choose based on your needs.

---

## Testing Error Paths

### **The Challenge**

Many error conditions are impossible to trigger with real dependencies:

```elixir
case File.read(path) do
  {:ok, content} -> process(content)
  {:error, :enoent} -> # File not found - EASY to test
  {:error, :eacces} -> # Permission denied - HARD to test
  {:error, :emfile} -> # Too many open files - IMPOSSIBLE to test reliably
end
```

---

### **The Solution: Mocked Error Returns**

```elixir
@tag :unit
test "handles permission denied error" do
  # Mock File module to return specific error
  mock_file = %{
    read: fn _path -> {:error, :eacces} end
  }

  result = MyModule.process_file("test.txt", file: mock_file)
  assert {:error, :permission_denied} = result
end

@tag :unit
test "handles too many files error" do
  mock_file = %{
    read: fn _path -> {:error, :emfile} end
  }

  result = MyModule.process_file("test.txt", file: mock_file)
  assert {:error, :retry_later} = result
end
```

---

### **Testing User Input Branches**

```elixir
# Your code has multiple branches based on user input
def ask_user do
  answer = IO.gets("Continue? (y/n): ")
  case String.trim(answer) do
    "y" -> proceed()
    "n" -> cancel()
    _ -> ask_user()  # Try again
  end
end
```

**Problem:** Cannot programmatically provide input to IO.gets.

**Solution:** Inject IO behavior:

```elixir
def ask_user(io \\ IO) do
  answer = io.gets("Continue? (y/n): ")
  case String.trim(answer) do
    "y" -> proceed()
    "n" -> cancel()
    _ -> ask_user(io)
  end
end
```

**Tests:**
```elixir
test "user answers yes" do
  mock_io = %{gets: fn _prompt -> "y\n" end}
  assert :proceeded = ask_user(mock_io)
end

test "user answers no" do
  mock_io = %{gets: fn _prompt -> "n\n" end}
  assert :cancelled = ask_user(mock_io)
end

test "user provides invalid input then yes" do
  # Returns sequence of inputs
  mock_io = %{gets: sequence(["invalid\n", "y\n"])}
  assert :proceeded = ask_user(mock_io)
end
```

---

## CI/CD Configuration

### **GitHub Actions**

**File:** `.github/workflows/test.yml`

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Install dependencies
        run: mix deps.get

      - name: Run unit tests (no external dependencies)
        run: mix test --only unit

      - name: Run integration tests (if database available)
        run: mix test --only integration
        env:
          DATABASE_URL: postgres://localhost/test
```

---

### **GitLab CI**

**File:** `.gitlab-ci.yml`

```yaml
test:
  image: elixir:1.15

  before_script:
    - mix local.hex --force
    - mix local.rebar --force
    - mix deps.get

  script:
    # Fast tests that don't need external services
    - mix test --only unit

    # Integration tests with services
    - mix test --only integration

  services:
    - postgres:14

  variables:
    DATABASE_URL: "postgres://postgres@postgres/test"
```

---

### **Docker Testing**

```dockerfile
# Dockerfile.test
FROM elixir:1.15-alpine

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . .

# Run tests inside container
CMD ["mix", "test"]
```

**Run:**
```bash
docker build -f Dockerfile.test -t myapp-test .
docker run myapp-test
```

---

## Parallel Test Execution

### **Enabling Async Tests**

```elixir
defmodule MyModuleTest do
  use ExUnit.Case, async: true  # ← Enable parallel execution

  test "independent test 1" do
    # Runs in parallel with other async tests
  end

  test "independent test 2" do
    # Runs in parallel with other async tests
  end
end
```

**Rules:**
- ✅ Tests must be isolated (no shared state)
- ✅ Tests must not depend on order
- ❌ Tests that modify global state must be synchronous

---

### **Parallel-Safe vs. Unsafe**

```elixir
# SAFE for parallel execution (uses mocks)
@tag :unit
test "validates email format" do
  mock_db = MockDB.new()
  assert {:error, :invalid_email} = register("bad-email", db: mock_db)
end

# UNSAFE for parallel execution (modifies real database)
@tag :integration
test "creates user in database" do
  # If two tests run in parallel, they conflict!
  DB.insert(:users, %{id: 1})  # ← Race condition
end
```

**Solution:** Tag integration tests to run synchronously:

```elixir
defmodule IntegrationTest do
  use ExUnit.Case, async: false  # ← Synchronous

  # Or at module level
  @moduletag :integration
  @moduletag :serial
end
```

**Run configuration:**
```bash
# Run unit tests in parallel (fast)
mix test --only unit

# Run integration tests serially (safe)
mix test --only integration --max-cases 1
```

---

## Mock Implementation Patterns

### **Pattern 1: Simple Map Mock**

```elixir
# Simple mock for one-off tests
test "example" do
  mock = %{
    function_name: fn arg -> {:ok, "result"} end
  }

  result = MyModule.call(mock)
end
```

**Pros:** Quick, no extra files
**Cons:** No reusability, no compile-time checking

---

### **Pattern 2: Behaviour-Based Mock**

```elixir
# test/support/mocks/repository.ex
defmodule MyApp.Mocks.Repository do
  @behaviour MyApp.Ports.Repository

  # Implements all callbacks with fake implementations
  @impl true
  def fetch_data(_id), do: {:ok, %{id: 1, name: "mock"}}

  @impl true
  def save_data(_data), do: :ok
end
```

**Pros:** Compile-time verified, reusable
**Cons:** More boilerplate

---

### **Pattern 3: Configurable Mock with Agent**

```elixir
defmodule MyApp.Mocks.ConfigurableRepository do
  use Agent

  def start_link(opts \\ []) do
    Agent.start_link(fn -> opts end, name: __MODULE__)
  end

  def configure(key, value) do
    Agent.update(__MODULE__, &Keyword.put(&1, key, value))
  end

  def fetch_data(id) do
    Agent.get(__MODULE__, fn config ->
      # Return configured result or default
      Keyword.get(config, :fetch_result, {:ok, %{id: id}})
    end)
  end
end
```

**Usage:**
```elixir
setup do
  {:ok, _} = ConfigurableRepository.start_link()
  :ok
end

test "handles fetch error" do
  ConfigurableRepository.configure(:fetch_result, {:error, :not_found})

  assert {:error, :not_found} = MyModule.get_item(1)
end
```

**Pros:** Highly flexible, test-specific behavior
**Cons:** More complex, requires process management

---

### **Pattern 4: Mox Library (Advanced)**

**Install:**
```elixir
# mix.exs
def deps do
  [{:mox, "~> 1.0", only: :test}]
end
```

**Define mock:**
```elixir
# test/test_helper.exs
Mox.defmock(MyApp.MockRepository, for: MyApp.Ports.Repository)
```

**Use in tests:**
```elixir
import Mox

test "example" do
  expect(MockRepository, :fetch_data, fn id ->
    {:ok, %{id: id, name: "mocked"}}
  end)

  # Mox verifies the function was called
  MyModule.get_item(1, repo: MockRepository)
end
```

**Pros:** Verification of calls, type-safe
**Cons:** Additional dependency

---

## Complete Example

### **Step 1: Define Port**

```elixir
# lib/my_app/ports/http_client.ex
defmodule MyApp.Ports.HTTPClient do
  @callback get(url :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback post(url :: String.t(), body :: map()) :: {:ok, map()} | {:error, term()}
end
```

### **Step 2: Real Implementation**

```elixir
# lib/my_app/adapters/httpoison_client.ex
defmodule MyApp.Adapters.HTTPoisonClient do
  @behaviour MyApp.Ports.HTTPClient

  @impl true
  def get(url) do
    case HTTPoison.get(url) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}
      {:ok, %{status_code: code}} ->
        {:error, {:http_error, code}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def post(url, body) do
    json = Jason.encode!(body)
    case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200, body: response}} ->
        {:ok, Jason.decode!(response)}
      error ->
        {:error, error}
    end
  end
end
```

### **Step 3: Mock Implementation**

```elixir
# test/support/mocks/http_client.ex
defmodule MyApp.Mocks.HTTPClient do
  @behaviour MyApp.Ports.HTTPClient

  @impl true
  def get("http://example.com/users/1") do
    {:ok, %{"id" => 1, "name" => "Alice"}}
  end
  def get(_url) do
    {:error, :not_found}
  end

  @impl true
  def post(_url, _body) do
    {:ok, %{"status" => "created"}}
  end
end
```

### **Step 4: Business Logic with DI**

```elixir
# lib/my_app/user_service.ex
defmodule MyApp.UserService do
  def fetch_user(id, opts \\ []) do
    http = Keyword.get(opts, :http, MyApp.Adapters.HTTPoisonClient)

    case http.get("http://example.com/users/#{id}") do
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### **Step 5: Integration Test (Real HTTP)**

```elixir
@tag :integration
@tag :external_api
test "fetches real user from API" do
  # Uses REAL HTTP client (default)
  assert {:ok, user} = UserService.fetch_user(1)
  assert user["id"] == 1
end
```

### **Step 6: Unit Tests (Mocked)**

```elixir
@tag :unit
test "handles network timeout" do
  # Mock that simulates timeout
  mock_http = %{
    get: fn _url -> {:error, :timeout} end
  }

  assert {:error, :timeout} = UserService.fetch_user(1, http: mock_http)
end

@tag :unit
test "handles 404 response" do
  mock_http = %{
    get: fn _url -> {:error, :not_found} end
  }

  assert {:error, :not_found} = UserService.fetch_user(999, http: mock_http)
end

@tag :unit
test "successfully fetches user" do
  # Use predefined mock
  assert {:ok, user} = UserService.fetch_user(1, http: MyApp.Mocks.HTTPClient)
  assert user["name"] == "Alice"
end
```

### **Step 7: Run Different Test Suites**

```bash
# Fast unit tests (mocked, parallel)
mix test --only unit

# Slow integration tests (real HTTP, serial)
mix test --only integration

# Everything
mix test

# Exclude tests that need external API
mix test --exclude external_api
```

---

## LLM Prompts

Use these prompts when asking an LLM to implement testable Elixir code:

---

### **Prompt 1: Implement with Dependency Injection**

```
I need you to implement [FEATURE] in Elixir with full testability using dependency injection.

Requirements:
1. Define a port (behaviour) in lib/my_app/ports/ that specifies the interface for [EXTERNAL_DEPENDENCY]
2. Implement a real adapter in lib/my_app/adapters/ that implements the port using [ACTUAL_LIBRARY]
3. Implement the business logic that accepts the dependency as an optional parameter with a sensible default
4. Create a mock implementation in test/support/mocks/ for testing

The code should follow hexagonal architecture principles:
- Core business logic is pure and dependency-free
- All I/O goes through ports
- Ports are implemented by adapters
- Business logic accepts adapters via dependency injection

Example structure:
- lib/my_app/ports/[name].ex - Behaviour definition
- lib/my_app/adapters/[name].ex - Real implementation
- lib/my_app/[module].ex - Business logic with DI
- test/support/mocks/[name].ex - Mock implementation

Make sure all adapters use @behaviour and @impl annotations for compile-time verification.
```

---

### **Prompt 2: Write Comprehensive Tests**

```
I need you to write comprehensive tests for [MODULE] using ExUnit with a three-tier testing strategy:

Tier 1 - Integration Tests (tag: :integration):
- Test happy paths with real dependencies
- Test critical workflows end-to-end
- Use actual database/filesystem/network when available

Tier 2 - Unit Tests (tag: :unit):
- Test error paths using mocked dependencies
- Test edge cases and boundary conditions
- Test all conditional branches
- Should run fast and require no external services

Tier 3 - Property Tests (optional, tag: :property):
- Use StreamData to test with randomized inputs
- Verify properties hold for all inputs

Requirements:
- Tag all tests appropriately (@tag :unit, @tag :integration)
- Make unit tests async (use ExUnit.Case, async: true)
- Make integration tests synchronous (async: false)
- Use descriptive test names that explain what is being tested
- Use describe blocks to group related tests
- Include both positive and negative test cases

Test structure:
- test/[module]_test.exs - Unit tests (mocked)
- test/integration/[module]_integration_test.exs - Integration tests (real)

Make sure all error paths are covered, not just happy paths.
```

---

### **Prompt 3: Configure CI/CD**

```
I need you to set up CI/CD testing for this Elixir project.

Requirements:
1. Create a GitHub Actions workflow (.github/workflows/test.yml) that:
   - Runs on push and pull request
   - Sets up Elixir [VERSION] and OTP [VERSION]
   - Installs dependencies
   - Runs unit tests (fast, no external dependencies)
   - Runs integration tests (with database if needed)
   - Reports coverage

2. Configure test environment (config/test.exs) to use mocked adapters

3. Add appropriate test tags to separate fast/slow tests

The workflow should be optimized for speed:
- Cache dependencies
- Run unit tests first (fail fast)
- Run integration tests only if unit tests pass
- Support parallel execution where safe

Make sure tests can run in a clean Docker container without external setup.
```

---

### **Prompt 4: Add Parallel Test Support**

```
I need you to update these tests to support parallel execution using ExUnit.

Requirements:
1. Identify which tests can run in parallel (stateless, no shared resources)
2. Mark those tests with async: true
3. Identify which tests must run serially (database writes, file system modifications)
4. Mark those tests with async: false
5. Add appropriate tags (@tag :parallel, @tag :serial)
6. Ensure all async tests are completely isolated

For tests that modify shared state:
- Use ExUnit's setup and on_exit callbacks to clean up
- Or use unique identifiers (UUIDs) to avoid conflicts
- Or mark them as synchronous

Goal: Maximize test suite speed while maintaining correctness.
```

---

### **Prompt 5: Create Mock Implementations**

```
I need you to create a mock implementation of [PORT/BEHAVIOUR] for testing.

Requirements:
1. Implement the [BEHAVIOUR] behaviour with @behaviour annotation
2. Use @impl true for all callback implementations
3. Return sensible fake data that mimics real responses
4. Include configurable failure modes (errors, timeouts, invalid data)
5. Add a way to verify calls were made (optional)

The mock should:
- Be located in test/support/mocks/[name].ex
- Implement all required callbacks from the behaviour
- Return realistic test data
- Support both success and failure scenarios
- Be configurable for different test cases (optional: use Agent for state)

Make the mock useful for testing all code paths, not just happy paths.
```

---

### **Prompt 6: Test Error Paths**

```
I need you to write tests that specifically cover error handling in [MODULE].

Focus on testing:
1. Network failures (timeout, connection refused, DNS failure)
2. File system errors (permission denied, disk full, file not found)
3. Database errors (connection lost, constraint violation, deadlock)
4. Invalid input (malformed data, wrong types, out of range)
5. Unexpected states (race conditions, partial failures)

For each error case:
- Use mocked dependencies that return the specific error
- Verify the code handles it gracefully
- Check that appropriate errors are returned to the caller
- Ensure resources are cleaned up properly

Do NOT just test happy paths. The goal is to prove the code is robust under failure conditions.
```

---

### **Meta-Prompt: Testing Strategy**

```
You are implementing an Elixir application using hexagonal architecture and comprehensive testing.

ALWAYS follow these principles:

1. **Dependency Injection:**
   - Define ports (behaviours) for all external dependencies
   - Implement real adapters for production
   - Implement mock adapters for testing
   - Accept dependencies as optional parameters with sensible defaults

2. **Testing Tiers:**
   - Integration tests (@tag :integration): Test happy paths with real dependencies
   - Unit tests (@tag :unit): Test error paths and edge cases with mocks
   - Make unit tests async, integration tests synchronous

3. **Error Coverage:**
   - Test ALL error paths, not just happy paths
   - Use mocks to simulate failures that are hard to trigger
   - Cover all conditional branches

4. **CI/CD Ready:**
   - Unit tests must run without external dependencies
   - Configuration-based mocking for test environment
   - Fast feedback (unit tests complete in seconds)

5. **ExUnit Best Practices:**
   - Use descriptive test names
   - Group related tests in describe blocks
   - Tag tests appropriately
   - Enable async where safe

When implementing any feature:
1. First define the port (behaviour)
2. Then implement the real adapter
3. Then implement the mock adapter
4. Then write the business logic with DI
5. Finally write comprehensive tests (unit + integration)

Provide compile-time safety using @behaviour and @impl annotations everywhere.
```

---

## Quick Reference Card

### **Testing Commands**
```bash
mix test                      # Run all tests
mix test --only unit          # Run unit tests only
mix test --only integration   # Run integration tests only
mix test --exclude slow       # Exclude slow tests
mix test --stale              # Run only changed tests
mix test --failed             # Re-run failed tests
mix test --trace              # Detailed output
mix test --cover              # Generate coverage report
```

### **Test Tags**
```elixir
@tag :unit              # Fast, mocked test
@tag :integration       # Slow, real dependencies
@tag :external_api      # Requires external service
@tag :slow              # Takes >1 second
@moduletag :serial      # Entire module runs serially
```

### **ExUnit Configuration**
```elixir
use ExUnit.Case, async: true    # Parallel execution
use ExUnit.Case, async: false   # Serial execution
```

### **Dependency Injection Pattern**
```elixir
def function(arg, opts \\ []) do
  dependency = Keyword.get(opts, :dependency, RealImplementation)
  dependency.call(arg)
end
```

---

**End of Testing Guide**

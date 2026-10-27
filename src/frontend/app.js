const form = document.querySelector("#name-form");
const input = document.querySelector("#name-input");
const message = document.querySelector("#message");
const list = document.querySelector("#name-list");
const emptyState = document.querySelector("#empty-state");
const addButton = document.querySelector("#add-button");
const queryButton = document.querySelector("#query-button");
const deleteButton = document.querySelector("#delete-button");
const actionButtons = [addButton, queryButton, deleteButton].filter(Boolean);

function showMessage(text, isError = false) {
  message.textContent = text;
  message.classList.toggle("error", isError);
}

async function apiRequest(url, options = {}) {
  const response = await fetch(url, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || "The request failed.");
  return body;
}

function renderNames(names) {
  list.replaceChildren();
  emptyState.hidden = names.length > 0;
  emptyState.textContent = "No names are currently stored.";

  names.forEach((record) => {
    const item = document.createElement("li");
    const details = document.createElement("div");
    const name = document.createElement("span");
    const date = document.createElement("span");

    name.className = "name";
    name.textContent = record.name;
    date.className = "date";
    date.textContent = `Added ${record.created_at} UTC`;

    details.append(name, date);
    item.append(details);
    list.append(item);
  });
}

async function loadNames() {
  setBusy(true);
  try {
    const data = await apiRequest("/api/get_names");
    renderNames(data.names);
    showMessage(`Query complete: ${data.names.length} name(s) found.`);
  } catch (error) {
    showMessage(error.message, true);
  } finally {
    setBusy(false);
  }
}

function setBusy(isBusy) {
  actionButtons.forEach((button) => {
    button.disabled = isBusy;
  });
}

async function removeName() {
  const name = input.value.trim();
  if (!name) {
    showMessage("Enter a name before deleting.", true);
    input.focus();
    return;
  }

  setBusy(true);
  try {
    await apiRequest("/api/remove_name", {
      method: "DELETE",
      body: JSON.stringify({ name }),
    });
    input.value = "";
    showMessage(`Deleted “${name}”. Select “Get names” to refresh the list.`);
    input.focus();
  } catch (error) {
    showMessage(error.message, true);
  } finally {
    setBusy(false);
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const name = input.value.trim();
  if (!name) {
    showMessage("Enter a name before adding.", true);
    input.focus();
    return;
  }

  setBusy(true);
  showMessage("");
  try {
    await apiRequest("/api/add_name", {
      method: "POST",
      body: JSON.stringify({ name }),
    });
    input.value = "";
    showMessage(`Added “${name}”. Select “Get names” to refresh the list.`);
    input.focus();
  } catch (error) {
    showMessage(error.message, true);
  } finally {
    setBusy(false);
  }
});

queryButton?.addEventListener("click", loadNames);
deleteButton?.addEventListener("click", removeName);

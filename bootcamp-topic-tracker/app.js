const STORAGE_KEY = "bootcamp-topic-tracker-v1";

const defaultBoard = [
  { id: crypto.randomUUID(), title: "Completed", completed: true, topics: [] },
  { id: crypto.randomUUID(), title: "Yet to Do", completed: false, topics: [] },
];

const boardElement = document.querySelector("#board");
const columnTemplate = document.querySelector("#column-template");
const topicTemplate = document.querySelector("#topic-template");
const columnDialog = document.querySelector("#column-dialog");
const columnForm = document.querySelector("#column-form");
const columnNameInput = document.querySelector("#column-name");
const addColumnButton = document.querySelector("#add-column-button");
const progressPercent = document.querySelector("#progress-percent");
const progressFill = document.querySelector("#progress-fill");
const progressTrack = document.querySelector(".progress-track");
const progressDetail = document.querySelector("#progress-detail");

let board = loadBoard();
let draggedTopic = null;

function loadBoard() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    return Array.isArray(saved) && saved.length ? saved : defaultBoard;
  } catch {
    return defaultBoard;
  }
}

function saveBoard() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(board));
}

function render() {
  boardElement.replaceChildren();

  board.forEach((column) => {
    const columnFragment = columnTemplate.content.cloneNode(true);
    const columnElement = columnFragment.querySelector(".column");
    const titleElement = columnFragment.querySelector(".column-title");
    const countElement = columnFragment.querySelector(".topic-count");
    const topicList = columnFragment.querySelector(".topic-list");
    const addTopicForm = columnFragment.querySelector(".add-topic-form");
    const deleteColumnButton = columnFragment.querySelector(".column-menu");

    columnElement.dataset.columnId = column.id;
    columnElement.dataset.completed = String(column.completed);
    titleElement.textContent = column.title;
    countElement.textContent = column.topics.length;
    deleteColumnButton.title = `Delete ${column.title}`;

    column.topics.forEach((topic) => {
      const topicFragment = topicTemplate.content.cloneNode(true);
      const topicCard = topicFragment.querySelector(".topic-card");
      const topicText = topicFragment.querySelector(".topic-text");
      const deleteButton = topicFragment.querySelector(".delete-topic");

      topicCard.dataset.topicId = topic.id;
      topicText.textContent = topic.text;

      topicCard.addEventListener("dragstart", () => {
        draggedTopic = { topicId: topic.id, sourceColumnId: column.id };
        topicCard.classList.add("dragging");
      });

      topicCard.addEventListener("dragend", () => {
        draggedTopic = null;
        topicCard.classList.remove("dragging");
        document
          .querySelectorAll(".drag-over")
          .forEach((element) => element.classList.remove("drag-over"));
      });

      deleteButton.addEventListener("click", () => {
        column.topics = column.topics.filter((item) => item.id !== topic.id);
        saveBoard();
        render();
      });

      topicList.append(topicFragment);
    });

    topicList.addEventListener("dragover", (event) => {
      event.preventDefault();
      topicList.classList.add("drag-over");
    });

    topicList.addEventListener("dragleave", () => {
      topicList.classList.remove("drag-over");
    });

    topicList.addEventListener("drop", (event) => {
      event.preventDefault();
      topicList.classList.remove("drag-over");
      moveTopic(column.id);
    });

    addTopicForm.addEventListener("submit", (event) => {
      event.preventDefault();
      const input = addTopicForm.elements.topic;
      const text = input.value.trim();

      if (!text) return;

      column.topics.push({ id: crypto.randomUUID(), text });
      input.value = "";
      saveBoard();
      render();
    });

    deleteColumnButton.addEventListener("click", () => {
      const message = column.topics.length
        ? `Delete "${column.title}" and its ${column.topics.length} topic(s)?`
        : `Delete "${column.title}"?`;

      if (window.confirm(message)) {
        board = board.filter((item) => item.id !== column.id);
        saveBoard();
        render();
      }
    });

    boardElement.append(columnFragment);
  });

  updateProgress();
}

function moveTopic(destinationColumnId) {
  if (!draggedTopic || draggedTopic.sourceColumnId === destinationColumnId) return;

  const sourceColumn = board.find(
    (column) => column.id === draggedTopic.sourceColumnId,
  );
  const destinationColumn = board.find(
    (column) => column.id === destinationColumnId,
  );
  const topicIndex = sourceColumn?.topics.findIndex(
    (topic) => topic.id === draggedTopic.topicId,
  );

  if (!sourceColumn || !destinationColumn || topicIndex < 0) return;

  const [topic] = sourceColumn.topics.splice(topicIndex, 1);
  destinationColumn.topics.push(topic);
  saveBoard();
  render();
}

function updateProgress() {
  const total = board.reduce((sum, column) => sum + column.topics.length, 0);
  const completed = board
    .filter((column) => column.completed)
    .reduce((sum, column) => sum + column.topics.length, 0);
  const percentage = total ? Math.round((completed / total) * 100) : 0;

  progressPercent.textContent = `${percentage}%`;
  progressFill.style.width = `${percentage}%`;
  progressTrack.setAttribute("aria-valuenow", percentage);
  progressDetail.textContent = total
    ? `${completed} of ${total} topic${total === 1 ? "" : "s"} completed.`
    : "Add your first topic to get started.";
}

addColumnButton.addEventListener("click", () => {
  columnForm.reset();
  columnDialog.showModal();
  requestAnimationFrame(() => columnNameInput.focus());
});

columnForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const submitterValue = event.submitter?.value;

  if (submitterValue === "cancel") {
    columnDialog.close();
    return;
  }

  const title = columnNameInput.value.trim();
  if (!title) return;

  board.push({
    id: crypto.randomUUID(),
    title,
    completed: /complete|done|finished/i.test(title),
    topics: [],
  });
  saveBoard();
  columnDialog.close();
  render();
});

columnDialog.addEventListener("click", (event) => {
  if (event.target === columnDialog) columnDialog.close();
});

render();

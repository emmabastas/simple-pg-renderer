answers = []

let i = 0
for (let node of document.querySelectorAll(".attemptResults .answer-preview")) {
  if (i % 2 == 1) {
    answers.push(node)
  }
  i++
}

document.addEventListener("keypress", revealAnswers)

function revealAnswers () {
  for (let i = 0; i < answers.length; i++) {
    answerInput = document.getElementById("mq-answer-AnSwEr" + (i + 1).toString().padStart(4, "0"))

    spoiler = document.createElement("div")
    spoiler.style.display = "inline-block"
    spoiler.appendChild(answers[i])

    answerInput.parentNode.replaceChild(spoiler, answerInput)
  }
}

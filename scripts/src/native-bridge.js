module.exports = (input, call) => {
  try {
    const result = call(input)
    return JSON.stringify(result)
  } catch (e) {
    console.log("INVOKE ERROR: ", e.toString(), e)
    return JSON.stringify({
      script_error: e.toString()
    })
  }
}

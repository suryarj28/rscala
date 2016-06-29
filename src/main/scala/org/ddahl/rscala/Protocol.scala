package org.ddahl.rscala

object Protocol {

  // Data Types
  val UNSUPPORTED_TYPE = 0
  val INTEGER = 1
  val DOUBLE =  2
  val BOOLEAN = 3
  val STRING =  4

  // Data Structures
  val UNSUPPORTED_STRUCTURE = 10
  val NULLTYPE  = 11
  val REFERENCE = 12
  val ATOMIC    = 13
  val VECTOR    = 14
  val MATRIX    = 15

  // Commands
  val EXIT          = 100
  val RESET         = 101
  val GC            = 102
  val DEBUG         = 103
  val EVAL          = 104
  val EVALNAKED     = 113
  val SET           = 105
  val SET_SINGLE    = 106
  val SET_DOUBLE    = 107
  val GET           = 108
  val GET_REFERENCE = 109
  val DEF           = 110
  val INVOKE        = 111
  val SCALAP        = 112

  // Result
  val OK = 1000
  val ERROR = 1001
  val UNDEFINED_IDENTIFIER = 1002

  // Misc.
  val CURRENT_SUPPORTED_SCALA_VERSION = "2.11.8"

}

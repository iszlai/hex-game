package com.hexgame.model

/**
  * Created by leheli on 2016.07.31..
  */
object HexState {
sealed trait HexState
  case object BLANK
  case object BLOCKED

}

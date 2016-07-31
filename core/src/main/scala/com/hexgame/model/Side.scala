package com.hexgame.model

/**
  * Created by leheli on 2016.07.31..
  */
sealed trait Side
object Side {

  case object SIDE_A extends Side
  case object SIDE_B extends Side
  case object SIDE_C extends Side
  case object SIDE_D extends Side
  case object SIDE_E extends Side
  case object SIDE_F extends Side

  val sides = Array(SIDE_A,SIDE_B,SIDE_C,SIDE_D,SIDE_E,SIDE_F)

  def getRandomSide():Side=sides(((Math.random()*sides.length ) % 10).toInt)
}

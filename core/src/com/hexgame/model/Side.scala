package com.hexgame.model

/**
  * Created by leheli on 2016.07.31..
  */
sealed abstract class Side(val char:String){
  def getTexture ():String  ="hex_" + char + ".png"
}
object Side {

  case object SIDE_A extends Side("A")
  case object SIDE_B extends Side("B")
  case object SIDE_C extends Side("C")
  case object SIDE_D extends Side("D")
  case object SIDE_E extends Side("E")
  case object SIDE_F extends Side("F")

  val sides = Array(SIDE_A,SIDE_B,SIDE_C,SIDE_D,SIDE_E,SIDE_F)

  def getRandomSide():Side=sides(((Math.random()*sides.length ) % 10).toInt)

}

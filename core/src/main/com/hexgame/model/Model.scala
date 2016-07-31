package com.hexgame.model
import scala.collection.mutable
import scala.collection.mutable.ListBuffer

/**
  * Created by leheli on 2016.07.31..
  */


 class World {
  val entities=new ListBuffer[Entity]

}

abstract class Entity(val position: Position){
  val events=new mutable.Queue[ToEntityEvent]()
}

class Hex2(pos: Position) extends Entity(pos){

}

case class Position(x:Byte,y:Byte,z:Byte)

class Hive {
  val map = mutable.Map[Position,Entity]()

  val positions=Seq(
    //row1
    Position(0,3,-3) ,
    Position(1,2,-3) ,
    Position(2,1,-3) ,
    Position(3,0,-3) ,
    //row2
    Position(-1,3,-2) ,
    Position(0,2,-2) ,
    Position(1,1,-2) ,
    Position(2,0,-2) ,
    Position(3,1,-2) ,
    //row3
    Position(-2,3,-1),
    Position(0,1,-1) ,
    Position(1,0,-1) ,
    Position(2,-1,-1) ,
    Position(3,-2,-1) ,
    //center row4
    Position(-3,3,0) ,
    Position(-2,2,0) ,
    Position(-1,1,0) ,
    Position(0,0,0) ,
    Position(1,-1,0) ,
    Position(2,-2,0) ,
    Position(3,-3,0) ,
    //row5
    Position(-3,2,1) ,
    Position(-2,1,1) ,
    Position(-1,0,1) ,
    Position(0,-1,1) ,
    Position(1,-2,1) ,
    Position(2,-3,1) ,
    //row6
    Position(-3,1,2) ,
    Position(-2,0,2) ,
    Position(-1,-1,2) ,
    Position(0,-2,2) ,
    Position(1,-3,2) ,
    //row7
    Position(-3,0,3) ,
    Position(-2,-1,3) ,
    Position(-1,-2,3) ,
    Position(0,-3,3)
  )

  positions.foreach{ pos =>
    val entry=new Hex2(pos)
    map += (pos-> entry)
  }

}

class ToEntityEvent

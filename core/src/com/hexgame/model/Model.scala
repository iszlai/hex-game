package com.hexgame.model





import scala.collection.mutable
import scala.collection.mutable.ListBuffer

/**
  * Created by leheli on 2016.07.31..
  */

class World {
  val entities=new ListBuffer[Entity]
  val hive:Hive=new Hive
    hive.map.values.foreach( entities.+=)
  val nextItem=new NexItem(Position(30,30,0),Side.getRandomSide())
}

abstract class Entity(val position: Position){
  val events=new mutable.Queue[ToEntityEvent]()
  def handleEvents
}

class HexEntitie(pos: Position) extends Entity(pos){
  private var state=HexState.BLANK
  def handleEvents:Unit={
   events.foreach(_ =>println("handling Event"))
 }

  def getNeighbourPosition(side:Side):Position  ={
    side match {
      case Side.SIDE_A => Position(pos.x,pos.y,pos.z)
      case Side.SIDE_B => Position(pos.x,pos.y,pos.z)
      case Side.SIDE_C => Position(pos.x,pos.y,pos.z)
      case Side.SIDE_D => Position(pos.x,pos.y,pos.z)
      case Side.SIDE_E => Position(pos.x,pos.y,pos.z)
      case Side.SIDE_F => Position(pos.x,pos.y,pos.z)
    }
  }
}

class NexItem(pos: Position,var side:Side) extends Entity(pos){
  def handleEvents={

  }
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
    val entry=new HexEntitie(pos)
    map += (pos-> entry)
  }

}

sealed trait ToEntityEvent
case object TouchEvent extends ToEntityEvent


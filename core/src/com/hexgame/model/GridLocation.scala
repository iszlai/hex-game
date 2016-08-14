package com.hexgame.model

import com.hexgame.model.Side._

/**
  * Created by leheli on 2016.08.01..
  */
class GridLocation(x: Int = 0, y: Int = 0, z: Int = 0) {


  def getNeighbour(side: Side): GridLocation = {
    var neighbour: GridLocation = null
    side match {
      case SIDE_A => {
        neighbour = new GridLocation(x, y + 1, z - 1)

      }
      case SIDE_B => {
        neighbour = new GridLocation(x + 1, y, z - 1)

      }
      case SIDE_C => {
        neighbour = new GridLocation(x + 1, y - 1, z)

      }
      case SIDE_D => {
        neighbour = new GridLocation(x, y - 1, z + 1)

      }
      case SIDE_E => {
        neighbour = new GridLocation(x - 1, y, z + 1)

      }
      case SIDE_F => {
        neighbour = new GridLocation(x - 1, y + 1, z)

      }
      case _ => {
        neighbour = this
      }
    }
    return neighbour
  }

  override def toString: String = {
    return "GL:{" + "x=" + x + ", y=" + y + ", z=" + z + '}'
  }
}

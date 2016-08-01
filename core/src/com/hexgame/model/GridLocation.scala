package com.hexgame.model

/**
  * Created by leheli on 2016.08.01..
  */
class GridLocation {
  val x: Int = 0
  val y: Int = 0
  val z: Int = 0

  def this(x: Int, y: Int, z: Int) {
    this()
    this.x = x
    this.y = y
    this.z = z
  }

  override def equals(o: AnyRef): Boolean = {
    if (this eq o) return true
    if (o == null || getClass ne o.getClass) return false
    val that: GridLocation = o.asInstanceOf[GridLocation]
    if (x != that.x) return false
    if (y != that.y) return false
    return z == that.z
  }

  override def hashCode: Int = {
    var result: Int = x
    result = 31 * result + y
    result = 31 * result + z
    return result
  }

  def getNeighbour(side: Sides): GridLocation = {
    var neighbour: GridLocation = null
    side match {
      case SIDE_A => {
        neighbour = new GridLocation(x, y + 1, z - 1)
        break //todo: break is not supported
      }
      case SIDE_B => {
        neighbour = new GridLocation(x + 1, y, z - 1)
        break //todo: break is not supported
      }
      case SIDE_C => {
        neighbour = new GridLocation(x + 1, y - 1, z)
        break //todo: break is not supported
      }
      case SIDE_D => {
        neighbour = new GridLocation(x, y - 1, z + 1)
        break //todo: break is not supported
      }
      case SIDE_E => {
        neighbour = new GridLocation(x - 1, y, z + 1)
        break //todo: break is not supported
      }
      case SIDE_F => {
        neighbour = new GridLocation(x - 1, y + 1, z)
        break //todo: break is not supported
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

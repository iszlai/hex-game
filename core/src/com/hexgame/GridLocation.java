package com.hexgame;

/**
 * Created by leheli on 2016.03.19..
 */
public class GridLocation {

    public final int x;
    public final int y;
    public final int z;

    public GridLocation(int x, int y, int z) {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;

        GridLocation that = (GridLocation) o;

        if (x != that.x) return false;
        if (y != that.y) return false;
        return z == that.z;

    }

    @Override
    public int hashCode() {
        int result = x;
        result = 31 * result + y;
        result = 31 * result + z;
        return result;
    }


    public GridLocation getNeighbour(Sides side){
        GridLocation neighbour;

        switch (side){
            case SIDE_A: {
                neighbour=new GridLocation(x,y+1,z-1);
                break;
            }
            case SIDE_B:{
                neighbour=new GridLocation(x+1,y,z-1);
                break;
            }
            case  SIDE_C:{
                neighbour=new GridLocation(x+1,y-1,z);
                break;
            }
            case SIDE_D:{
                neighbour=new GridLocation(x,y-1,z+1);
                break;
            }
            case SIDE_E:{
                neighbour=new GridLocation(x-1,y,z+1);
                break;
            }
            case SIDE_F:{
                neighbour=new GridLocation(x-1,y+1,z);
                break;
            }
            default:{
                neighbour=this;
            }
        }
        return  neighbour;
    }

    @Override
    public String toString() {
        return "GL:{" +
                "x=" + x +
                ", y=" + y +
                ", z=" + z +
                '}';
    }
}
